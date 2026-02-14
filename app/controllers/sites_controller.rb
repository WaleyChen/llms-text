class SitesController < ApplicationController
  def index
    @sites = Site.order(created_at: :desc)
    respond_to do |format|
      format.json { render json: @sites }
      format.html { redirect_to root_path }
    end
  end

  def create
    attrs = site_params.to_h
    attrs[:url] = normalize_url(attrs[:url]) if attrs[:url].present?
    @site = Site.new(attrs)
    if @site.save
      @run = Run.create(site_id: @site.id, status: Run::STATUS_PENDING)
      GenerateLlmsTxtJob.perform_later(@run.id)
      redirect_to root_path, notice: "Site added."
    else
      redirect_to root_path, alert: @site.errors.full_messages.to_sentence
    end
  end

  private

  def site_params
    params.require(:site).permit(:url)
  end

  def normalize_url(url)
    url = url.to_s.strip
    return url if url.blank?
    return url if url.match?(%r{\Ahttps?://}i)
    "https://#{url}"
  end
end
