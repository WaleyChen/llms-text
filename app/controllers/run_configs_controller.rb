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

  def show
    @run_config = RunConfig.find(params[:id])
    respond_to do |format|
      format.json { render json: @run_config }
      format.html { redirect_to root_path }
    end
  end

  def create
    request.format = :json if request.headers["Accept"]&.include?("application/json")
    
    # Handle/Validate/Normalize attributes
    attrs = run_config_params.to_h
    url, error = validate_url(attrs[:url])
    if error
      return render_error(error)
    end
    attrs[:url] = url
    attrs[:max_pages] = attrs[:max_pages].to_s.blank? ? 200 : attrs[:max_pages].to_i
    attrs[:max_depth] = attrs[:max_depth].to_s.blank? ? 3 : attrs[:max_depth].to_i
    attrs[:model] = attrs[:model].presence || Run::MODEL_NONE

    # Create the run config and runs in a transaction
    @run_config = RunConfig.new(
      url: attrs[:url],
      status: RunConfig::STATUS_PENDING,
      max_pages: attrs[:max_pages],
      max_depth: attrs[:max_depth],
      model: attrs[:model]
    )
    ActiveRecord::Base.transaction do
      @run_config.save!

      models = @run_config.model == Run::MODEL_ALL ? Run::MODELS : [@run_config.model]
      @runs = models.map do |model|
        next if model == Run::MODEL_CLAUDE_SONNET_4_5 && ENV["ANTHROPIC_API_KEY"].blank?
        next if model == Run::MODEL_GPT_5_2 && ENV["OPENAI_API_KEY"].blank?
        Run.create!(run_config_id: @run_config.id, status: Run::STATUS_PENDING, model: model)
      end
    end

    CrawlJob.perform_later(@run_config.id)

    respond_to do |format|
      format.json { render json: { run_config: @run_config, runs: @runs }, status: :created }
      format.html { redirect_to root_path, notice: "Run config added." }
    end
  rescue ActiveRecord::RecordInvalid # Handle validation errors
    respond_to do |format|
      format.json { render json: { errors: @run_config.errors.full_messages }, status: :unprocessable_entity }
      format.html { redirect_to root_path, alert: @run_config.errors.full_messages.to_sentence }
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

  # Validates the URL and returns the normalized URL or an error message
  # Validates the URL by:
  # - Rejecting blank URLs
  # - Rejecting URLs that do not contain a valid domain (e.g. example.com)
  # - Rejecting non-http/https protocols like ftp://, mailto://, etc.
  # - Rejecting URLs that are not valid (e.g. the URL is not a valid URL)
  # - Rejecting URLs pointing to private or local networks (e.g. 127.0.0.1, localhost, etc.)
  # - Rejecting URLs that are not reachable (e.g. the URL is not responding to requests)
  def validate_url(raw)
    url = raw.to_s.strip

    return [nil, "URL can't be blank."] if url.blank?
    return [nil, "URL must contain a valid domain (e.g. example.com)."] unless url.include?(".")

    # Validate the URL is a valid URL by parsing it with URI.parse
    url = "https://#{url}" unless url.match?(%r{\A\w+://}i) # Prepend https if no scheme
    return [nil, "Only http and https URLs are supported."] unless url.match?(%r{\Ahttps?://}i) # Reject non-http/https protocols
    uri = URI.parse(url)
    return [nil, "URL is not valid."] unless uri.host.present?

    uri.query = nil # Remove query parameters
    uri.fragment = nil # Remove fragment, the part after the # symbol
    url = uri.to_s

    # Rejects URLs pointing to private or local networks (e.g. 127.0.0.1, localhost, etc.)
    ip = Resolv.getaddress(uri.host)
    if PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
      return [nil, "URLs pointing to private or local networks are not allowed."]
    end

    # Try to connect to the URL (https or http)
    candidates = url.match?(%r{\Ahttps?://}i) ? [url] : ["https://#{url}", "http://#{url}"]
    candidates.each do |candidate|
      return [candidate, nil] if reachable?(candidate)
    end

    [nil, "URL is not reachable. Please check the URL and try again."]
  rescue URI::InvalidURIError => e
    Rails.logger.warn("[URL Validation] Invalid URI for #{raw}: #{e.message}")
    [nil, "URL is not valid."]
  rescue Resolv::ResolvError => e
    Rails.logger.warn("[URL Validation] DNS resolution failed for #{uri.host}: #{e.message}")
    [nil, "Could not resolve hostname. Please check the URL."]
  end

  # Checks if the URL is reachable by trying HEAD first, then GET if HEAD fails (some sites reject HEAD)
  def reachable?(url)
    conn = Faraday.new do |f|
      f.response :follow_redirects, limit: 3
      f.adapter Faraday.default_adapter
    end
    
    # Try HEAD first (faster, no body)
    begin
      response = conn.head(url) do |req|
        req.headers["User-Agent"] = "llms-txt-fetcher/0.1"
        req.options.timeout = 10
        req.options.open_timeout = 5
      end
      # Accept 2xx/3xx as success; also accept 403/429 as "reachable" (site exists, just blocking)
      status_ok = response.status < 400 || [403, 429].include?(response.status)
      Rails.logger.debug("[Reachability] HEAD #{url}: #{response.status}") if Rails.env.development?
      return status_ok
    rescue Faraday::Error => e
      Rails.logger.debug("[Reachability] HEAD #{url} failed: #{e.class} - #{e.message}") if Rails.env.development?
      # HEAD failed, try GET (some sites like Quora reject HEAD)
    end
    
    # Fallback to GET with range header to limit body size
    begin
      response = conn.get(url) do |req|
        req.headers["User-Agent"] = "llms-txt-fetcher/0.1"
        req.headers["Range"] = "bytes=0-1023" # Only fetch first 1KB
        req.options.timeout = 10
        req.options.open_timeout = 5
      end
      # Accept 2xx/3xx as success; also accept 403/429 as "reachable" (site exists, just blocking)
      status_ok = response.status < 400 || [403, 429].include?(response.status)
      Rails.logger.debug("[Reachability] GET #{url}: #{response.status}") if Rails.env.development?
      status_ok
    rescue Faraday::Error => e
      Rails.logger.debug("[Reachability] GET #{url} failed: #{e.class} - #{e.message}") if Rails.env.development?
      false
    end
  end
end
