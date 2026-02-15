# frozen_string_literal: true

require "set"

module LlmsTxt
  class Crawler
    # IMPORTANT_PATHS = %w[/docs /documentation /api /about /guide /guides /tutorial /tutorials /help /support].freeze
    DEFAULT_MAX_PAGES = 20
    DEFAULT_MAX_DEPTH = 3
    CONCURRENCY = 4

    def initialize(base_url, max_pages: nil, max_depth: nil)
      @base_url = normalize_url(base_url)
      @base_uri = URI.parse(@base_url)
      @scheme = @base_uri.scheme
      @max_pages = max_pages || DEFAULT_MAX_PAGES
      @max_depth = max_depth || DEFAULT_MAX_DEPTH
      @visited = Set.new
      @pages = []
      @mutex = Mutex.new
    end

    def crawl
      crawl_page(@base_url, depth: 0)
      @pages
    end

    private

    # Normalize a URL by:
    # - Stripping whitespace
    # - Prepending the scheme if no scheme
    # - Removing query parameters and fragment
    # - Returning the normalized URL
    def normalize_url(url)
      url = url.to_s.strip
      url = "#{@scheme}://#{url}" unless url.match?(%r{\Ahttps?://}i) # prepend scheme if no scheme
      uri = URI.parse(url)
      uri.query = nil # remove query parameters
      uri.fragment = nil # remove fragment, the part after the # symbol
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    # Scheme-agnostic key so http and https versions of the same page count as one visit.
    def visited_key(url)
      uri = URI.parse(url)
      path = uri.path.to_s.empty? ? "/" : uri.path
      "#{uri.host}#{path}"
    rescue URI::InvalidURIError
      url
    end

    def crawl_page(url, parent_url: nil, depth: 0)
      url = normalize_url(url)
      visited_key = visited_key(url)
      @mutex.synchronize do
        return if depth > @max_depth || @visited.include?(visited_key) || @pages.size >= @max_pages
        @visited.add(visited_key)
      end

      body = nil
      begin
        response = LlmsTxt::Fetcher.get(url)
        status = response.status.to_i
        if status >= 200 && status < 300
          body = response.body
        else
          Rails.logger.warn("[Fetcher] Failed to fetch #{url}: #{response.status}")
          return
        end
      rescue Faraday::Error, SocketError, URI::InvalidURIError => e
        Rails.logger.warn("[Fetcher] Failed to fetch #{url}: #{e.message}")
        return
      end

      doc = Nokogiri::HTML(body)
      extractor = PageExtractor.new(doc, url)

      page_data = extractor.to_h.merge(url: url)
      page_data[:content] = extract_main_content(doc)
      page_data[:parent_url] = parent_url
      page_data[:depth] = depth

      links_to_follow = nil
      @mutex.synchronize do
        @pages << page_data
        if depth < @max_depth && @pages.size < @max_pages
          links_to_follow = collect_follow_links(doc, url, depth + 1)
        end
      end

      if Rails.env.development?
        # puts "doc: #{doc.inspect}"
        puts "links_to_follow: #{links_to_follow.inspect}"
      end

      return if links_to_follow.blank?

      # Crawl follow links in parallel (thread pool)
      links_to_follow.each_slice(CONCURRENCY) do |batch|
        threads = batch.map do |link|
          Thread.new { crawl_page(link, parent_url: url, depth: depth + 1) }
        end
        threads.each(&:join)
      end
    end

    def collect_follow_links(doc, current_url, depth)
      links = doc.css("a[href]").map do |a|
        href = a["href"]&.strip
        next if href.blank? || href.start_with?("#", "javascript:", "mailto:")

        absolute_url(href, current_url)
      end.compact.uniq

      same_domain = links.select { |link| same_domain?(link) }
    end

    def same_domain?(url)
      return false unless url.start_with?("http://", "https://")

      uri = URI.parse(url)
      uri.host == @base_uri.host
    rescue URI::InvalidURIError
      false
    end

    def absolute_url(href, base_url)
      return href if href.match?(%r{\Ahttps?://}i)

      base = URI.parse(base_url)
      URI.join(base, href).to_s
    rescue URI::InvalidURIError
      nil
    end

    def extract_main_content(doc)
      # Try semantic HTML5 elements first
      main = doc.at_css("main, article, [role='main']")
      return clean_text(main) if main

      # Fallback: get text from body, excluding nav/footer/script/style
      body = doc.at_css("body")
      return "" unless body

      # Remove script, style, nav, footer
      body.css("script, style, nav, footer, header").remove
      clean_text(body)
    end

    def clean_text(element)
      return "" unless element

      text = element.text
      # Normalize whitespace
      text.gsub(/\s+/, " ").strip
    end
  end
end
