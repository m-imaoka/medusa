class Analysis < ActiveRecord::Base
  include HasRecordProperty
  include HasViewSpot
  include HasAttachmentFile

  PERMIT_IMPORT_TYPES = ["text/plain", "text/csv", "application/csv", "application/vnd.ms-excel"]

  has_many :chemistries
  has_many :referrings, as: :referable, dependent: :destroy
  has_many :bibs, through: :referrings
  belongs_to :specimen
  belongs_to :device
  belongs_to :technique

  validates :specimen, existence: true, allow_nil: true
  validates :device, existence: true, allow_nil: true
  validates :technique, existence: true, allow_nil: true
  validates :name, presence: true, length: { maximum: 255 }

  before_update :update_table_analyses

  MeasurementCategory.all.each do |mc|
    comma mc.name.to_sym do
      name "name"
      name "device_name"
      name "technique_name"
      name "description"
      name "operator"
      name "specimen_global_id"
      mc.export_headers.map { |header| name header }
    end
  end


  def related_spots
    return [] unless specimen
    specimen.related_spots
  end

  def chemistry_summary(length=100)
    display_names = chemistries.map { |ch| ch.display_name if ch.measurement_item }.compact
    display_names.join(", ").truncate(length)
  end

  def specimen_global_id
    specimen.try!(:global_id)
  end

  def specimen_global_id=(global_id)
    self.specimen = Specimen.joins(:record_property).where(record_properties: {global_id: global_id}).first
  end

  def device_name=(name)
    self.device_id = Device.find_by(name: name).try(:id)
  end

  def technique_name=(name)
    self.technique_id = Technique.find_by(name: name).try(:id)
  end

  def self.import_csv(file)
    if file && PERMIT_IMPORT_TYPES.include?(file.content_type)
      objects = build_objects_from_csv(file)
      if objects.all?(&:valid?)
        objects.map {|obj| obj.save}
      else
        false
      end
    end
  end

  def self.build_objects_from_csv(file)
    csv = CSV.parse(file.read, row_sep: :auto)
    methods = csv.shift.compact.map {|column| column.gsub(/ /,'_')}
    csv.inject([]) do |objects, row|
      objects + [set_object(methods, row)] if row.any?(&:present?)
    end
  end

  def self.set_object(methods, data_array)
    data_array.each { |data| data.strip! unless data.blank? }
    pkey_value = methods.index("id") ? data_array[methods.index("id")] : nil
    object = Analysis.find_or_initialize_by(id: pkey_value)
    object.attributes = Hash[methods.zip(data_array)]
    object
  end

  def method_missing(method_name, *arguments)
    if (method_name.to_s =~ /^(.+?)(_error)?(?:_in_(.+))?(=)?$/) && MeasurementItem.exists?(nickname: $1)
      if $4.present?
        if $2.present?
          set_uncertainty($1, arguments[0])
        else
          set_chemistry($1, $3, arguments[0])
        end
      elsif $2.blank?
        get_chemistry_value($1, $3)
      else
        super
      end
    else
      super
    end
  end

  def set_chemistry(measurement_item_name, unit_name, data)
    measurement_item = MeasurementItem.find_by(nickname: measurement_item_name)
    value = data
    value.strip! if value.is_a? String
    if value
      unless unit_name
        if measurement_item.unit
          unit_name = measurement_item.unit.name
        else
          unit_name = "parts"
        end
      end
      unit = Unit.find_by(name: unit_name)
      chemistries.build(measurement_item_id: measurement_item.id, value: value, unit_id: unit.try(:id))
    end
  end

  def set_uncertainty(measurement_item_name, data)
    chemistry = associate_chemistry_by_item_nickname(measurement_item_name)
    if chemistry
      uncertainty = data
      uncertainty.strip! if uncertainty.is_a? String
      chemistry.uncertainty = uncertainty
    end
  end

  def get_chemistry_value(measurement_item_name, unit_name)
    chemistry = associate_chemistry_by_item_nickname(measurement_item_name)
    if chemistry
      if chemistry.unit
        return chemistry.value.send(chemistry.unit.name).to(unit_name.to_sym).value
      end
      chemistry.value
    end
  end

  def associate_chemistry_by_item_nickname(nickname)
    chemistries.joins(:measurement_item).merge(MeasurementItem.where(nickname: nickname)).first
  end

  def self.to_castemls(objs)
    xml = ::Builder::XmlMarkup.new(indent: 2)
    xml.instruct!
    xml.acquisitions do
      objs.each do |obj|
        obj.to_pml(xml) if obj.respond_to?(:to_pml)
      end
    end
  end

  def to_pml(xml=nil)
    unless xml
      xml = ::Builder::XmlMarkup.new(indent: 2)
      xml.instruct!
    end
    xml.acquisition do
      xml.global_id(global_id)
      xml.name(name)
      xml.device(device.try!(:name))
      xml.technique(technique.try!(:name))
      xml.operator(operator)
      xml.sample_global_id(specimen.try!(:global_id))
      xml.sample_name(specimen.try!(:name))
      xml.description(description)
      spot = get_spot
      if spot
        xml.spot do
          xml.global_id(spot.global_id)
          xml.attachment_file_global_id(spot.attachment_file.try!(:global_id))
          xml.x_image(spot.spot_x_from_center)
          xml.y_image(spot.spot_y_from_center)
          xml.x_overpic(spot.spot_overpic_x)
          xml.y_overpic(spot.spot_overpic_y)         
          world_xy = spot.spot_world_xy
          if world_xy
            xml.x_vs(world_xy[0])
            xml.y_vs(world_xy[1]) 
          end
        end
      end
      unless chemistries.empty?
        xml.chemistries do
          chemistries.each do |chemistry|
            xml.analysis do
              xml.nickname(chemistry.measurement_item.try!(:nickname))
              xml.value(chemistry.value)
              xml.unit(chemistry.unit.try!(:text))
              xml.uncertainty(chemistry.uncertainty)
              xml.label(chemistry.label)
              xml.info(chemistry.info)
            end
          end
        end
      end
    end
    
  end

  def get_spot
    spots = Spot.where(target_uid: global_id)
    return if spots.empty?
    spots[0]
  end

  private

  def update_table_analyses
    return unless specimen_id_changed?
    TableAnalysis.delete_all(analysis_id: id)
    TableSpecimen.where(specimen_id: specimen_id).each do |table_specimen|
      max_priority = TableAnalysis.where(table_id: table_specimen.table_id, specimen_id: table_specimen.specimen_id).maximum(:priority) || 0
      TableAnalysis.create!(table_id: table_specimen.table_id, specimen_id: table_specimen.specimen_id, analysis_id: id, priority: (max_priority + 1))
    end
  end

end
