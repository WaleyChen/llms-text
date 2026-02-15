# frozen_string_literal: true

require "faraday/retry"
require "ostruct"

module LlmsTxt
  class Fetcher
    CACHE_EXPIRY = 15.minutes

    class << self
      def connection
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
        cache_key = "llms_txt_fetcher/#{Digest::SHA256.hexdigest(url)}"
        cached = Rails.cache.read(cache_key)
        return response_with_body(cached) if cached

        response = connection.get(url) do |req|
          req.headers["User-Agent"] = "llms-txt-fetcher/0.1"
          req.options.timeout = 5        # 5 minutes
          req.options.open_timeout = 5   # 5 minutes
        end
        Rails.cache.write(cache_key, response.body, expires_in: CACHE_EXPIRY)
        response
      end

      private

      def response_with_body(body)
        OpenStruct.new(body: body, status: 200)
      end
    end
  end
end
