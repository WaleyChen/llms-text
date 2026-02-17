class RunConfigsController < ApplicationController
  def index
    @run_configs = RunConfig.order(created_at: :desc)
    if Rails.env.development?
      puts "@run_configs: #{@run_configs.inspect.pretty_inspect}"
    end
    respond_to do |format|
      format.json { render json: @run_configs }
      format.html { redirect_to root_path }
    end
  end

  def create
    request.format = :json if request.headers["Accept"]&.include?("application/json")
    attrs = run_config_params.to_h
    if Rails.env.development?
      puts "attrs: #{attrs.inspect.pretty_inspect}"
    end
    attrs[:url] = normalize_url(attrs[:url]) if attrs[:url].present?
    if attrs[:url].blank?
      respond_to do |format|
        format.json { render json: { errors: ["URL can't be blank."] }, status: :unprocessable_entity }
        format.html { redirect_to root_path, alert: "URL can't be blank." }
      end
      return
    end
    
    attrs[:max_pages] = attrs[:max_pages].to_s.blank? ? 20 : attrs[:max_pages].to_i
    attrs[:max_depth] = attrs[:max_depth].to_s.blank? ? 3 : attrs[:max_depth].to_i
    attrs[:model] = attrs[:model].presence || Run::MODEL_NONE

    @run_config = RunConfig.new(url: attrs[:url])
    @run_config.assign_attributes(attrs.slice(:max_pages, :max_depth, :model))

    if @run_config.save
      if @run_config.model == Run::MODEL_ALL
        @runs = []
        Run::MODELS.each do |model|
          @runs << Run.create!(run_config_id: @run_config.id, status: Run::STATUS_PENDING, model: model)
        end
      else
        @runs = [Run.create!(run_config_id: @run_config.id, status: Run::STATUS_PENDING, model: @run_config.model)]
      end

      CrawlJob.perform_later(@run_config.id)

      respond_to do |format|
        format.json { render json: { run_config: @run_config, runs: @runs }, status: :created }
        format.html { redirect_to root_path, notice: "Run config added." }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: @run_config.errors.full_messages }, status: :unprocessable_entity }
        format.html { redirect_to root_path, alert: @run_config.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def run_config_params
    params.require(:run_config).permit(:url, :max_pages, :max_depth, :model)
  end

  def normalize_url(url)
    url = url.to_s.strip
    return url if url.blank?
    return url if url.match?(%r{\Ahttps?://}i)
    "https://#{url}"
  end
end
