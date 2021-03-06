class SurfaceImagesController < ApplicationController
  respond_to :html, :xml, :json, :svg
  before_action :find_surface
  before_action :find_resource, except: [:index, :new, :create, :link_by_global_id]

#  load_and_authorize_resource

  def show
    #@surface_image = @surface.surface_images.find_by_image_id(@image.id)
    respond_with @surface_image
  end

  def family
    respond_with @spot, layout: !request.xhr?
  end

  def create
    @image = AttachmentFile.new(image_params)
    @surface.images << @image if @image.save
    respond_with @image, location: adjust_url_by_requesting_tab(request.referer), action: "error"      
  end


  def destroy
    #@image = AttachmentFile.find(params[:id])
    @surface.images.delete(@image)
    respond_with @image, location: adjust_url_by_requesting_tab(request.referer)
  end

  def update
    @image = AttachmentFile.find(params[:id])
    @surface.images << @image
    respond_with @image
  end

  def link_by_global_id
    @image = AttachmentFile.joins(:record_property).where(record_properties: {global_id: params[:global_id]}).readonly(false).first
    @surface.images << @image if @image
    respond_with @image, location: adjust_url_by_requesting_tab(request.referer), action: "error"
  rescue
    duplicate_global_id
  end

  def move_to_top
    #@surface.surface_images.find_by_image_id(@image.id).move_to_top
    @surface_image.move_to_top
    respond_with @image, location: adjust_url_by_requesting_tab(request.referer)
  end

  private

  def image_params
    params.require(:attachment_file).permit(
      :name,
      :description,
      :md5hash,
      :data,
      :original_geometry,
      :affine_matrix_in_string,
      :user_id,
      :group_id,
      :published,
      record_property_attributes: [
        :id,
        :global_id,
        :user_id,
        :group_id,
        :owner_readable,
        :owner_writable,
        :group_readable,
        :group_writable,
        :guest_readable,
        :guest_writable,
        :lost
      ]
    )
  end

  def find_surface
  	@surface = Surface.find(params[:surface_id]).decorate
  end

  def find_resource
  	@image = AttachmentFile.find(params[:id])
    @surface_image = @surface.surface_images.find_by_image_id(@image.id).decorate
  end


  def duplicate_global_id
    respond_to do |format|
      format.html { render "parts/duplicate_global_id", status: :unprocessable_entity }
      format.all { render nothing: true, status: :unprocessable_entity }
    end
  end  
end
