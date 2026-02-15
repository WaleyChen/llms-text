# frozen_string_literal: true

module LlmsTxt
  class Generator
    def initialize(pages, model)
      @pages = pages
      @homepage = pages.first
      @model = model
    end

    def generate
      lines = []
      lines << "# #{@homepage[:title] || 'Untitled'}"
      lines << ""
      lines << "> #{homepage_description}"
      lines << ""

      overview_pages = pages_for_overview
      unless overview_pages.empty?
        lines << "## Overview"
        lines << ""
        overview_pages.each do |page|
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

      first_path_segments.each do |segment|
        section_pages = pages_for_first_segment(segment)
        next if section_pages.size <= 1

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

    def homepage_description
      return generate_description_via_openai if use_ai_description?
      return @homepage[:description] if @homepage[:description].to_s.strip != ""

      "No description available."
    end

    def use_ai_description?
      return true if @model.to_s.downcase.in?(%w[gpt-5.2-mini])
      return false if @model.blank?
      return false if @model.to_s.downcase.in?(%w[n/a none])

      ENV["OPENAI_API_KEY"].present?
    end

    def generate_description_via_openai
      puts "Generating description via OpenAI for model: #{@model}"

      llm = Langchain::LLM::OpenAI.new(
        api_key: ENV["OPENAI_API_KEY"],
        default_options: { chat_model: openai_model, temperature: 0.3 }
      )
      content = build_description_context
      prompt = <<~PROMPT
        Write a brief 1-2 sentence description for this website's llms.txt file.
        Be concise and informative. Output only the description, no quotes or preamble.

        Site title: #{@homepage[:title] || 'Untitled'}
        Content excerpt:
        #{content}
      PROMPT
      response = llm.chat(messages: [{ role: "user", content: prompt }])
      response.chat_completion.to_s.strip.presence || "No description available."
    rescue Exception => e
      Rails.logger.warn("[Generator] OpenAI description failed: #{e.message}")
      "No description available."
    end

    def openai_model
      case @model.to_s.downcase
      when "gpt-4o" then "gpt-4o"
      when "opus-4.6", "claude-3.5" then "gpt-4o" # map non-OpenAI to gpt-4o
      else "gpt-4o"
      end
    end

    def build_description_context
      text = @homepage[:content].to_s.strip
      return "No content available." if text.blank?

      # Truncate to ~2000 chars to stay within token limits
      text.length > 2000 ? "#{text[0...2000]}..." : text
    end

    def path_segment_count(url)
      uri = URI.parse(url)
      path = uri.path.to_s
      path.split("/").reject(&:empty?).size
    rescue URI::InvalidURIError
      0
    end

    def pages_for_overview
      @pages
        .select { |p| path_segment_count(p[:url]) == 1 }
        .sort_by { |p| (p[:title] || extract_title_from_url(p[:url])).to_s.downcase }
    end

    def first_path_segments
      @pages.filter_map do |p|
        first_segment_for_url(p[:url])
      end.uniq.sort
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

# Here are focused suggestions for improving your llms.txt generation:
# 1. Section order
# first_path_segments keeps the order of first occurrence in @pages, so section order is effectively crawl order. For predictable output, sort segments (e.g. alphabetically) or define a priority list (e.g. put "docs" before "blog") and use that when iterating.
# 2. Page order within sections
# pages_for_first_segment keeps crawl order. Consider sorting by title, URL, or depth (e.g. shallow first) so the same run always produces the same ordering and important pages are easier to find.
# 3. Homepage / root in sections
# For https://example.com/ or path "/", first_segment_for_url returns nil (path has no segments), so the homepage never appears under any ## section—only in the header. If you want it listed in the body too, treat nil (or path "/") as a segment like "Home" or "Overview" and add a section for it.
# 4. Segment display names
# segment.capitalize gives "Contact-sales" for contact-sales. For nicer headings, humanize: replace -/_ with spaces and title-case (e.g. "Contact Sales").
# 5. Markdown safety
# If page[:title] or page[:description] contains ], (, or backticks, the list item can break. Escaping or stripping those characters (or wrapping in backticks where appropriate) keeps the output valid markdown.
# 6. Optional structure
# Table of contents: at the top, list each ## Segment as a link to an anchor (e.g. ## Blog → #blog) so the file is easier to navigate.
# Stable anchors: use a consistent slug (e.g. downcased segment, spaces → -) for ## headings so TOC links work.
# 7. Optional metadata
# If you have crawl time or run id, a short line like “Generated …” or “Last crawled …” at the top or bottom can help without changing the main structure.
# 8. Long descriptions
# If descriptions are long, truncate (e.g. first sentence or N characters) so the file stays scannable and link-heavy.
# 9. Empty / missing description
# You already use page[:description].to_s.strip != "". You could show a fallback (e.g. “No description”) only in dev, or leave it out in production so the line stays minimal.
# 10. Second-level grouping (optional)
# If you have deep trees (e.g. /docs/guides, /docs/api), you could group by first two path segments (e.g. “Docs > Guides”, “Docs > Api”) for subsections. That adds complexity; only worth it if the sites you crawl are highly structured.
# Most impact for minimal change: stable section order, stable page order within sections, and handling the root path so the homepage can appear in a section if you want it. Next: humanized segment names and markdown-safe titles/descriptions.