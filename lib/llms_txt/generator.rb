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

      # Group pages by section
      careers = @pages.select { |p| p[:url].match?(%r{/(career|careers)}i) }
      docs = @pages.select { |p| p[:url].match?(%r{/(docs?|documentation|api|guide|tutorial)}i) }
      blog = @pages.select { |p| p[:url].match?(%r{/(blog)}i) }
      other = @pages.reject { |p| docs.include?(p) || careers.include?(p) || blog.include?(p) || p == @homepage }

      if docs.any?
        lines << "## Documentation"
        lines << ""
        docs.each do |page|
          title = page[:title] || extract_title_from_url(page[:url])
          lines << "- [#{title}](#{page[:url]}): #{page[:description] || 'Documentation page'}"
        end
        lines << ""
      end

      if careers.any?
        lines << "## Careers"
        lines << ""
        careers.each do |page|
          title = page[:title] || extract_title_from_url(page[:url])
          lines << "- [#{title}](#{page[:url]})"
        end
        lines << ""
      end

      if blog.any?
        lines << "## Blog"
        lines << ""
        blog.each do |page|
          title = page[:title] || extract_title_from_url(page[:url])
          lines << "- [#{title}](#{page[:url]})"
        end
        lines << ""
      end

      if other.any?
        lines << "## Additional Resources"
        lines << ""
        other.each do |page|
          title = page[:title] || extract_title_from_url(page[:url])
          lines << "- [#{title}](#{page[:url]})"
        end
      end

      lines.join("\n")
    end

    private

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
