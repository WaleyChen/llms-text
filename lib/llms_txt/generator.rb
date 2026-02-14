# frozen_string_literal: true

module LlmsTxt
  class Generator
    def initialize(pages)
      @pages = pages
      @homepage = pages.first
    end

    def generate
      lines = []
      lines << "# #{@homepage[:title] || 'Untitled'}"
      lines << ""
      lines << "> #{@homepage[:description] || 'No description available.'}"
      lines << ""

      # Add any additional context from homepage content
      if @homepage[:content].present?
        summary = summarize(@homepage[:content], max_length: 200)
        lines << summary if summary.present?
        lines << ""
      end

      # Group pages by section
      docs = @pages.select { |p| p[:url].match?(%r{/(docs?|documentation|api|guide|tutorial)}i) }
      other = @pages.reject { |p| docs.include?(p) || p == @homepage }

      if docs.any?
        lines << "## Documentation"
        lines << ""
        docs.each do |page|
          title = page[:title] || extract_title_from_url(page[:url])
          lines << "- [#{title}](#{page[:url]}): #{page[:description] || 'Documentation page'}"
        end
        lines << ""
      end

      if other.any?
        lines << "## Additional Resources"
        lines << ""
        other.first(10).each do |page|
          title = page[:title] || extract_title_from_url(page[:url])
          lines << "- [#{title}](#{page[:url]})"
        end
      end

      lines.join("\n")
    end

    private

    def summarize(text, max_length:)
      return nil if text.blank?

      text = text.strip
      return text if text.length <= max_length

      # Try to cut at sentence boundary
      truncated = text[0, max_length]
      last_period = truncated.rindex(/[.!?]\s/)
      truncated = truncated[0, last_period + 1] if last_period
      truncated + "..."
    end

    def extract_title_from_url(url)
      uri = URI.parse(url)
      path = uri.path
      return "Home" if path == "/" || path.empty?

      path.split("/").last.gsub(/[-_]/, " ").split.map(&:capitalize).join(" ")
    rescue URI::InvalidURIError
      "Page"
    end
  end
end
