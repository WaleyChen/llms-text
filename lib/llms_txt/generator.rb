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

      first_path_segments.each do |segment|
        section_pages = pages_for_first_segment(segment)
        next if section_pages.empty?

        lines << "## #{segment.capitalize}"
        lines << ""
        section_pages.each do |page|
          title = page[:title] || extract_title_from_url(page[:url])
          line = "- [#{title}](#{page[:url]})"
          line += ": #{page[:description]}" if page[:description].to_s.strip != ""

          if Rails.env.development?
            line += " (depth: #{page[:depth]})"
            line += " (parent_url: #{page[:parent_url]})"
          end
          lines << line
        end
        lines << ""
      end

      lines.join("\n")
    end

    private

    def first_path_segments
      @pages.filter_map do |p|
        first_segment_for_url(p[:url])
      end.uniq
    end

    def first_segment_for_url(url)
      uri = URI.parse(url)
      path = uri.path
      path.split("/").reject(&:empty?).first
    rescue URI::InvalidURIError
      nil
    end

    def pages_for_first_segment(segment)
      @pages
        .select { |p| first_segment_for_url(p[:url]) == segment }
        .sort_by { |p| (p[:title] || extract_title_from_url(p[:url])).to_s.downcase } # sort by title, case-insensitive
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
