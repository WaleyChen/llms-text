class RunConfigsController < ApplicationController
  def index
    @run_configs = RunConfig.order(created_at: :desc)
    respond_to do |format|
      format.json { render json: @run_configs }
      format.html { redirect_to root_path }
    end
  end

  def create
    attrs = run_config_params.to_h
    attrs[:url] = normalize_url(attrs[:url]) if attrs[:url].present?
    @run_config = RunConfig.new(attrs)
    if @run_config.save
      @run = Run.create!(run_config_id: @run_config.id, status: Run::STATUS_PENDING)
      GenerateLlmsTxtJob.perform_later(@run.id)
      redirect_to root_path, notice: "Run config added."
    else
      redirect_to root_path, alert: @run_config.errors.full_messages.to_sentence
    end
  end

  private

  def run_config_params
    params.require(:run_config).permit(:url)
  end

  def normalize_url(url)
    url = url.to_s.strip
    return url if url.blank?
    return url if url.match?(%r{\Ahttps?://}i)
    "https://#{url}"
  end
end
