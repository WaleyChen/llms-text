# frozen_string_literal: true

require "faraday/retry"
require "ferrum"
require "nokogiri"
require "ostruct"

module LlmsTxt
  class Fetcher
    CACHE_EXPIRY = 1.day

    # Heuristics to detect JavaScript-rendered (SPA / client-side) pages.
    # Returns true if the page likely requires JS to display main content.
    def self.javascript_rendered?(html)
      return false if html.blank?

      doc = Nokogiri::HTML(html)
      body = doc.at_css("body")
      return false unless body

      # 1. Very little text content — likely a shell that JS fills in
      text = body.text.gsub(/\s+/, " ").strip
      return true if text.length < 300

      # 2. SPA framework markers in HTML
      raw = html.to_s
      return true if raw.include?("__NEXT_DATA__")
      return true if raw.include?("__NUXT__") || raw.include?("__NUXT_DATA__")
      return true if raw.include?("data-reactroot") || raw.include?("data-react-root")
      return true if raw.include?("ng-version") || raw.include?("ng-app")
      return true if raw.include?("litNonce") || raw.include?("lit.dev")

      # 3. Empty/minimal root divs (React, Vue, etc.)
      root = doc.at_css("#root, #app, #__next, [data-reactroot]")
      if root && root.text.gsub(/\s+/, " ").strip.length < 200
        return true
      end

      # 4. Custom elements (Web Components) — strong signal for JS-heavy/hybrid sites
      custom_tags = doc.css("shreddit-app-attrs, shreddit-async-loader, shreddit-page-meta, faceplate-tracker")
      return true if custom_tags.any?

      # 5. Meta generator indicating SPA frameworks
      generator = doc.at_css('meta[name="generator"]')&.[]("content")&.downcase.to_s
      return true if generator.include?("next.js") || generator.include?("nuxt") || generator.include?("gatsby")

      false
    end

    class << self
      def connection
        # 2 retries, 0.5 second interval, 2x backoff factor
        # After 1st failure: 0.5 × 2⁰ = 0.5s
        # After 2nd failure: 0.5 × 2¹ = 1s
        @connection ||= Faraday.new do |f|
          f.request :retry,
            max: 2,
            interval: 0.5,
            backoff_factor: 2,
            exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]

          f.response :follow_redirects, limit: 3
          f.adapter Faraday.default_adapter
        end
      end

      def get(url)
        cache_key = url_cache_key(url)
        cached = Rails.cache.read(cache_key)
        return response_with_body(cached) if cached

        response = connection.get(url) do |req|
          req.headers["User-Agent"] = "llms-txt-fetcher/0.1"
          req.options.timeout = 30      # the total number of seconds to wait for the whole response
          req.options.open_timeout = 10 # the numbers of seconds to establish a connection
        end

        body = response.body.to_s

        # If JS-rendered, refetch with headless browser for full content
        if response.success? && html_response?(response) && javascript_rendered?(body)
          puts "JavaScript-rendered page detected for #{url}, fetching with headless browser"
          ferrum_body = fetch_with_ferrum(url)
          body = ferrum_body if ferrum_body.present?
        end

        if response.success?
          Rails.cache.write(cache_key, body, expires_in: CACHE_EXPIRY)
        else
          Rails.logger.warn("[Fetcher] Failed to fetch #{url}: #{response.status}")
        end

        response_with_body(body, response.status)
      end

      private

      # Normalize URL for cache so /path and /path/ share the same entry
      def url_cache_key(url)
        uri = URI.parse(url.to_s)
        path = uri.path.to_s
        path = path.end_with?("/") && path != "/" ? path[0..-2] : path
        path = "/" if path.empty?
        uri.path = path
        uri.query = nil
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError
        url.to_s
      end

      def html_response?(response)
        content_type = response.headers["content-type"].to_s.downcase
        content_type.include?("text/html") || content_type.include?("application/xhtml")
      end

      def fetch_with_ferrum(url)
        browser = Ferrum::Browser.new(
          headless: true,
          timeout: 30,
          process_timeout: 10
        )
        browser.headers.set("User-Agent" => "llms-txt-fetcher/0.1")
        page = browser.create_page
        page.go_to(url)
        page.network.wait_for_idle(duration: 0.5, timeout: 15)
        html = page.body
        browser.quit
        html
      rescue StandardError => e
        Rails.logger.warn("[Fetcher] Ferrum fetch failed for #{url}: #{e.message}")
        nil
      end

      def response_with_body(body, status = 200)
        OpenStruct.new(body: body, status: status)
      end
    end
  end
end
