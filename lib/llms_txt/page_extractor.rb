# frozen_string_literal: true

module LlmsTxt
  class PageExtractor
    attr_reader :doc, :page_url

    def initialize(doc, page_url)
      @doc = doc
      @page_url = page_url
    end

    def title
      doc.at_css("title")&.text&.strip.presence ||
        doc.at_css('meta[property="og:title"]')&.[]("content")&.strip.presence
    end

    # All markdown-style links [text](url) from the page (for context)
    def associated_urls
      urls = []
      doc.css("a[href]").each do |a|
        href = a["href"]&.strip
        next if href.blank? || href.start_with?("#", "javascript:", "mailto:")

        urls << absolute_url(href)
      end
      urls.compact.uniq
    end

    def to_h
      {
        title: title,
        associated_urls: associated_urls
      }
    end

    private

    def base_uri
      URI.parse(page_url)
    rescue URI::InvalidURIError
      nil
    end

    def absolute_url(href)
      return nil if href.blank?

      base = base_uri
      return href if base.nil? || href.match?(%r{\Ahttps?://}i)

      URI.join(base, href).to_s
    rescue URI::InvalidURIError
      nil
    end
  end
end
