# frozen_string_literal: true

require "faraday/retry"

module LlmsTxt
  class Crawler
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
        connection.get(url) do |req|
          req.headers["User-Agent"] = "llms-txt-crawler/0.1"
          req.options.timeout = 5
          req.options.open_timeout = 2
        end
      end
    end
  end
end
