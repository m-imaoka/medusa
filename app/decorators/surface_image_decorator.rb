class SurfaceImageDecorator < Draper::Decorator
  include Rails.application.routes.url_helpers	
  delegate_all

  # Define presentation-specific methods here. Helpers are accessed through
  # `helpers` (aka `h`). You can override attributes, for example:
  #
  #   def created_at
  #     helpers.content_tag :span, class: 'time' do
  #       object.created_at.strftime("%a %m/%d/%y")
  #     end
  #   end

  def to_tex
    q_url = "http://dream.misasa.okayama-u.ac.jp/?q="
    basename = File.basename(image.name,".*")
    lines = []
    lines << "\\begin{overpic}[width=0.49\\textwidth]{#{basename}}"
    lines << "\\put(1,74){\\colorbox{white}{(\\sublabel{#{basename}}) \\href{#{q_url}#{image.global_id}}{#{basename}}}}"
    lines << "%%(\\subref{#{basename}}) \\nolinkurl{#{basename}}"
    lines << "\\color{red}"

    surface.surface_images.each do |osurface_image|
      oimage = osurface_image.image
      #image_region
      opixels = oimage.spots.map{|spot| [spot.spot_x, spot.spot_y]}
      worlds = oimage.pixel_pairs_on_world(opixels)
      pixels = image.world_pairs_on_pixel(worlds)
      oimage.spots.each_with_index do |spot, idx|
        length = image.length
        height = image.height
        x = "%.1f" % (pixels[idx][0] / length * 100)
        y = "%.1f" % (height.to_f / length * 100 - pixels[idx][1] / length * 100)
        line = "\\put(#{x},#{y})"
        line += "{\\footnotesize \\circle{0.7} \\href{#{q_url}#{spot.target_uid}}{#{spot.name}}}"
        line += " % #{spot.target_uid}" if spot.target_uid
        line += " % \\vs(#{("%.1f" %  worlds[idx][0])}, #{("%.1f" % worlds[idx][1])})"
        lines << line
      end
    end

    width_on_stage = image.transform_length(image.width / image.length * 100)
    scale_length_on_stage = 10 ** (Math::log10(width_on_stage).round - 1)
    scale_length_on_image = image.transform_length(scale_length_on_stage, :world2xy).round
    lines << "%%scale #{("%.0f" % scale_length_on_stage)}\ micro meter"
    lines << "\\put(1,1){\\line(1,0){#{("%.1f" % scale_length_on_image)}}}"

    lines << "\\end{overpic}"

    lines.join("\n")
  end

  def target_path
    surface_image_path(surface, self.image, script_name: Rails.application.config.relative_url_root)
  end
end
