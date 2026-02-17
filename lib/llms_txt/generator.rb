# frozen_string_literal: true

require "set"

module LlmsTxt
  class Generator
    def initialize(run, pages, failed_pages)
      @homepage = pages.first
      @pages = pages.drop(1) # drop the homepage from the pages array
      @num_pages_displayed = 0
      @displayed_urls = Set.new
      @failed_pages = failed_pages
      @model = run.model
    end

    def generate
      lines = []
      lines << "# #{@homepage[:title] || 'Untitled'}"
      lines << ""
      lines << "> #{homepage_description}"
      lines << ""

      if @model == Run::MODEL_NONE
        generate_with_no_model(lines)
      else
        generate_with_model(@model, lines)
      end
      add_debug_info(lines)

      lines.join("\n")
    end

    private

    def generate_with_no_model(lines)
      overview_pages = pages_for_overview
      unless overview_pages.empty?
        lines << "## Overview"
        lines << ""
        overview_pages.each do |page|
          @num_pages_displayed += 1
          @displayed_urls.add(page[:url])
          title = page[:title] || extract_title_from_url(page[:url])
          line = "- [#{title}](#{page[:url]})"
          line += ": #{page[:description]}" if page[:description].to_s.strip != ""

          # if @debug
          #   line += " (depth: #{page[:depth]})"
          #   line += " (parent_url: #{page[:parent_url]})"
          # end
          lines << line
        end
        lines << ""
      end

      first_path_segments.each do |segment|
        section_pages = pages_for_first_segment(segment)
        next if section_pages.length == 0
        # Skip pages with 1 path segment that are already included in the Overview section
        next if section_pages.length == 1 and path_segment_count(section_pages.first[:url]) <= 1

        lines << "## #{segment.capitalize}"
        lines << ""
        section_pages.each do |page|
          next if path_segment_count(page[:url]) <= 1 # Skip pages with 1 path segment since they are already in the Overview section
          @num_pages_displayed += 1
          @displayed_urls.add(page[:url])
          title = page[:title] || extract_title_from_url(page[:url])
          line = "- [#{title}](#{page[:url]})"
          line += ": #{page[:description]}" if page[:description].to_s.strip != ""

          # if @debug
          #   line += " (depth: #{page[:depth]})"
          #   line += " (parent_url: #{page[:parent_url]})"
          # end

          lines << line
        end
        lines << ""
      end
    end

    def generate_with_model(model, lines)
      return generate_with_no_model(lines) unless llm_available?
      sections = fetch_sections_from_llm
      render_llm_sections(sections, lines)
      render_missing_pages(lines)
    end

    def llm_available?
      if claude_model?
        ENV["ANTHROPIC_API_KEY"].present?
      else
        ENV["OPENAI_API_KEY"].present?
      end
    end

    def claude_model?
      @model.to_s.downcase == Run::MODEL_CLAUDE_SONNET_4_5.downcase
    end

    def fetch_sections_from_llm
      url_list = @pages.map do |p|
        title = p[:title] || extract_title_from_url(p[:url])
        desc = p[:description].to_s.strip
        line = "- #{p[:url]} (title: #{title})"
        line += " - #{desc.length > 80 ? "#{desc[0..80]}..." : desc}" if desc.present?
        line
      end.join("\n")

      prompt = <<~PROMPT
        Given these URLs from a website crawl, group them into logical sections for an llms.txt file.
        For each URL, provide:
        - title: clean, human-readable (fix casing, remove the product, company or website name from the title if it's present, remove extra words, make it concise)
        - description: a brief 1-2 sentence description for LLMs (what the page is about, who it's for)
        Return ONLY valid JSON. No markdown, no explanation.
        Format: {
          "Section Name": [
            {"url": "url1", "title": "Clean Title", "description": "Brief description for LLMs."},
            {"url": "url2", "title": "Another Title", "description": "..."}
          ],
          "Another Section": [
            {"url": "url3", "title": "Title", "description": "..."}
          ]
        }
        Use an "Overview" section for top-level pages (e.g. /about, /pricing).
        Group related pages (e.g. docs, blog) into their own sections.
        Order sections by importance (Overview first, then main sections).
        The sum of the number of urls across all sections must be the same as the number of urls in the input.

        URLs:
        #{url_list}
      PROMPT

      llm = if claude_model?
        Langchain::LLM::Anthropic.new(
          api_key: ENV["ANTHROPIC_API_KEY"],
          default_options: { chat_model: Run::MODEL_CLAUDE_SONNET_4_5, temperature: 0.2, max_tokens: 8192 }
        )
      else
        Langchain::LLM::OpenAI.new(
          api_key: ENV["OPENAI_API_KEY"],
          default_options: { chat_model: openai_model, temperature: 0.2 }
        )
      end

      if claude_model?
        puts "Claude model: #{llm.inspect.pretty_inspect}"
      end
      
      response = llm.chat(messages: [{ role: "user", content: prompt }])
      raw = response.chat_completion.to_s.strip
      # Strip markdown code blocks if present
      raw = raw.gsub(/\A```(?:json)?\s*/, "").gsub(/\s*```\z/, "")
      JSON.parse(raw)
    rescue StandardError => e
      Rails.logger.warn("[Generator] LLM section identification failed: #{e.message}")
      nil
    end

    def render_llm_sections(sections, lines)
      page_by_url = @pages.index_by { |p| p[:url].to_s }

      sections.each do |section_name, urls|
        next if urls.blank?

        lines << "## #{section_name}"
        lines << ""
        Array(urls).each do |item|
          url_str = item.is_a?(Hash) ? (item["url"] || item[:url]).to_s.strip : item.to_s.strip
          page = page_by_url[url_str] || page_by_url.values.find { |p| p[:url].to_s == url_str }
          next unless page

          @num_pages_displayed += 1
          @displayed_urls.add(page[:url])
          title = if item.is_a?(Hash) && (item["title"].present? || item[:title].present?)
            (item["title"] || item[:title]).to_s.strip
          else
            page[:title] || extract_title_from_url(page[:url])
          end
          description = if item.is_a?(Hash) && (item["description"].present? || item[:description].present?)
            (item["description"] || item[:description]).to_s.strip
          else
            page[:description].to_s.strip
          end
          line = "- [#{title}](#{page[:url]})"
          line += ": #{description}" if description.present?

          if Rails.env.development?
            line += " (depth: #{page[:depth]})"
            line += " (parent_url: #{page[:parent_url]})"
          end
          lines << line
        end
        lines << ""
      end
    end

    def render_missing_pages(lines)
      return if pages_not_displayed.empty?

      lines << "## Misc"
      lines << ""
      pages_not_displayed.each do |page|
        lines << "- [#{page[:title] || extract_title_from_url(page[:url])}](#{page[:url]}): #{page[:description].to_s.strip}"

        @num_pages_displayed += 1
        @displayed_urls.add(page[:url])
      end
    end

    # ------------------------------------------------------------

    def add_debug_info(lines)
      # if @debug
      #   lines << "## Total Pages: #{@pages.size}"
      #   lines << "## Total Pages Displayed: #{@num_pages_displayed}"
      #   lines << "## Total Failed Pages: #{@failed_pages.size}"
      #   lines << "## Pages Not Displayed (#{pages_not_displayed.size})"
      #   pages_not_displayed.each do |page|
      #     lines << "- #{page[:url]} (depth: #{page[:depth]}, segments: #{path_segment_count(page[:url])})"
      #   end
      #   lines << "## Failed Pages"
      #   lines << @failed_pages.inspect
      # end
    end

    def pages_not_displayed
      @pages.reject { |p| @displayed_urls.include?(p[:url]) }
    end

    def homepage_description
      return generate_description_via_openai if use_ai_description?
      return @homepage[:description] if @homepage[:description].to_s.strip != ""

      "No description available."
    end

    def use_ai_description?
      return true if @model.to_s.downcase == Run::MODEL_GPT_5_2_MINI
      return true if claude_model?
      return false if @model.blank?
      return false if @model.to_s.downcase.in?([Run::MODEL_NONE.downcase, "none"])

      llm_available?
    end

    def generate_description_via_openai
      puts "Generating description via LLM for model: #{@model}"

      llm = if claude_model?
        Langchain::LLM::Anthropic.new(
          api_key: ENV["ANTHROPIC_API_KEY"],
          default_options: { chat_model: Run::MODEL_CLAUDE_SONNET_4_5, temperature: 0.3, max_tokens: 512 }
        )
      else
        Langchain::LLM::OpenAI.new(
          api_key: ENV["OPENAI_API_KEY"],
          default_options: { chat_model: openai_model, temperature: 0.3 }
        )
      end
      content = build_description_context
      prompt = <<~PROMPT
        Write a brief 2-4 sentence description for this website's llms.txt file.
        Be concise and informative. Output only the description, no quotes or preamble.

        Site title: #{@homepage[:title] || 'Untitled'}
        Content excerpt:
        #{content}
      PROMPT
      response = llm.chat(messages: [{ role: "user", content: prompt }])
      response.chat_completion.to_s.strip.presence || "No description available."
    rescue StandardError => e
      Rails.logger.warn("[Generator] LLM description failed: #{e.message}")
      "No description available."
    end

    def openai_model
      case @model.to_s.downcase
      when "gpt-4o" then "gpt-4o"
      when "gpt-5.2-mini" then "gpt-4o-mini"
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

    # Returns the number of path segments in the URL
    # Examples:
    # https://example.com/ → 0
    # https://example.com/about → 1
    # https://example.com/docs/guides/getting-started → 3
    def path_segment_count(url)
      uri = URI.parse(url)
      path = uri.path.to_s
      path.split("/").reject(&:empty?).size
    rescue URI::InvalidURIError
      0
    end

    # Returns the pages for the overview section
    # The overview section is the pages with 1 path segment
    # Examples:
    # https://example.com/about
    # https://example.com/docs
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
        .select { |p| first_segment_for_url(p[:url]) == segment and path_segment_count(p[:url]) > 1 }
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