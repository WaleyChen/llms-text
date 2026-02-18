require "resolv"
require "ipaddr"

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
    
    # Handle attributes
    attrs = run_config_params.to_h
    url, error = validate_and_resolve_url(attrs[:url])
    if error
      return render_error(error)
    end
    attrs[:url] = url
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

  def render_error(message)
    respond_to do |format|
      format.json { render json: { errors: [message] }, status: :unprocessable_entity }
      format.html { redirect_to root_path, alert: message }
    end
  end

  PRIVATE_IP_RANGES = [
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("::1/128"),
  ].freeze

  # Returns [resolved_url, nil] on success or [nil, error_message] on failure.
  def validate_and_resolve_url(raw)
    url = raw.to_s.strip

    return [nil, "URL can't be blank."] if url.blank?
    return [nil, "URL must contain a valid domain (e.g. example.com)."] unless url.include?(".")

    if url.match?(%r{\A\w+://}i) && !url.match?(%r{\Ahttps?://}i)
      return [nil, "Only http and https URLs are supported."]
    end

    # Parse the URL and check if it's valid
    test_url = url.match?(%r{\Ahttps?://}i) ? url : "https://#{url}"
    uri = URI.parse(test_url)
    return [nil, "URL is not valid."] unless uri.host.present?

    ip = Resolv.getaddress(uri.host)
    if PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
      return [nil, "URLs pointing to private or local networks are not allowed."]
    end

    # Search https and http versions of the URL
    candidates = url.match?(%r{\Ahttps?://}i) ? [url] : ["https://#{url}", "http://#{url}"]
    candidates.each do |candidate|
      return [candidate, nil] if reachable?(candidate)
    end

    [nil, "URL is not reachable. Please check the URL and try again."]
  rescue URI::InvalidURIError
    [nil, "URL is not valid."]
  rescue Resolv::ResolvError
    [nil, "Could not resolve hostname. Please check the URL."]
  end

  def reachable?(url)
    conn = Faraday.new do |f|
      f.response :follow_redirects, limit: 3
      f.adapter Faraday.default_adapter
    end
    response = conn.head(url) do |req|
      req.options.timeout = 5
      req.options.open_timeout = 5
    end
    response.status < 400
  rescue Faraday::Error
    false
  end
end
