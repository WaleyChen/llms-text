class SitesController < ApplicationController
  def index
    @sites = Site.order(created_at: :desc)
    respond_to do |format|
      format.json { render json: @sites }
      format.html { redirect_to root_path }
    end
  end

  def create
    @site = Site.new(site_params)
    if @site.save
      @run = Run.create(site_id: @site.id, status: Run::STATUS_PENDING)
      @run.start()
      redirect_to root_path, notice: "Site added."
    else
      redirect_to root_path, alert: @site.errors.full_messages.to_sentence
    end
  end

  private

    def site_params
        params.require(:site).permit(:url)
    end
end
