class Surface < ActiveRecord::Base
  include HasRecordProperty
  has_many :surface_images, :dependent => :destroy
  has_many :images, through: :surface_images	
  validates :name, presence: true, length: { maximum: 255 }, uniqueness: true

  def spots
  	ss = []
  	image = first_image
    surface_images.each do |osurface_image|
      oimage = osurface_image.image
      #image_region
      opixels = oimage.spots.map{|spot| [spot.spot_x, spot.spot_y]}
      worlds = oimage.pixel_pairs_on_world(opixels)
      pixels = image.world_pairs_on_pixel(worlds)
      oimage.spots.each_with_index do |spot, idx|
      	spot.attachment_file_id = image.id
        spot.spot_x = pixels[idx][0]
        spot.spot_y = pixels[idx][1]
        ss << spot
      end
    end
  	ss
  end


  def first_image
  	surface_image = surface_images.order('position ASC').first
  	surface_image.image if surface_image
  end
end
