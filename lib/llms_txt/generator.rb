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
      debug_lines = []
      lines << "# #{@homepage[:title] || 'Untitled'}"
      lines << ""
      lines << "> #{homepage_description}"
      lines << ""

      if @model == Run::MODEL_NONE
        generate_with_no_model(lines)
      else
        generate_with_model(@model, lines, debug_lines)
      end
      add_debug_info(lines)

      {
        llms_txt: lines.join("\n"),
        debug_logs: debug_lines.join("\n")
      }
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

    def generate_with_model(model, lines, debug_lines)
      return generate_with_no_model(lines) unless llm_available?
      
      # Run grouping and title/description generation in parallel
      all_urls = @pages.map { |p| p[:url].to_s }
      page_by_url = @pages.index_by { |p| p[:url].to_s }
      
      sections_result = nil
      enriched_urls_map = {}
      
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      grouping_thread = Thread.new do
        sections_result = group_urls_into_sections(debug_lines)
      end
      
      enrichment_thread = Thread.new do
        enriched_urls_map = generate_titles_and_descriptions(all_urls, page_by_url, debug_lines)
      end
      
      grouping_thread.join
      enrichment_thread.join
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      debug_lines << "Step 3 - Total Latency: #{elapsed.round(2)} seconds"
      
      return generate_with_no_model(lines) unless sections_result
      
      # Merge grouping with enriched titles/descriptions
      enriched_sections = {}
      sections_result.each do |section_name, urls|
        enriched_sections[section_name] = urls.map do |url|
          enriched_urls_map[url.to_s] || { "url" => url.to_s }
        end
      end
      
      render_llm_sections(enriched_sections, lines)
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

    # Step 1: Group URLs into sections (no title/description generation)
    def group_urls_into_sections(debug_lines)
      pages_json = @pages.map do |p|
        title = p[:title] || extract_title_from_url(p[:url])
        desc = p[:description].to_s.strip
        desc = "#{desc[0..80]}..." if desc.length > 80
        { url: p[:url].to_s, title: title.to_s, description: desc }
      end
      pages_payload = JSON.generate(pages_json)

      debug_lines << "Step 1 - URLs passed for grouping: #{JSON.pretty_generate(pages_json)}"

      prompt = <<~PROMPT
        Given this JSON array of pages from a website crawl, group them into logical sections for an llms.txt file.
        Each page includes its existing title and meta description (if any) as context to help you understand what the page is about.
        
        Return ONLY valid JSON with this format (URLs only, no titles or descriptions):
        {
          "Section Name": ["url1", "url2", "url3"],
          "Another Section": ["url4", "url5"]
        }
        
        Rules:
        - Use an "Overview" section for top-level pages (e.g. /about, /pricing).
        - Group related pages (e.g. docs, blog) into their own sections.
        - Order sections by importance (Overview first, then main sections).
        - The sum of URLs across all sections must equal the number of items in the input array.
        - Return ONLY the JSON object, no markdown, no explanation.

        Input (JSON array of pages):
        #{pages_payload}
      PROMPT

      llm = create_llm_instance
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = llm.chat(messages: [{ role: "user", content: prompt }])
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      raw = response.chat_completion.to_s.strip
      raw = raw.gsub(/\A```(?:json)?\s*/, "").gsub(/\s*```\z/, "")
      json = JSON.parse(raw)
      debug_lines << "Step 1 - Grouping result: #{JSON.pretty_generate(json)}"
      debug_lines << "Step 1 - Grouping latency: #{elapsed.round(2)} seconds"
      json
    rescue StandardError => e
      Rails.logger.warn("[Generator] LLM grouping failed: #{e.message}")
      debug_lines << "Step 1 - Grouping failed: #{e.message}"
      nil
    end


    # Generate titles and descriptions for URLs
    def generate_titles_and_descriptions(urls, page_by_url, debug_lines)
      debug_lines << "Step 2 - Processing #{urls.size} URLs for title/description generation"
      
      # Check cache first
      cached_results = {}
      urls_to_fetch = []
      
      urls.each do |url|
        cache_key = "llm_enrichment:#{url}"
        cached = Rails.cache.read(cache_key)
        if cached
          cached_results[url.to_s] = cached
        else
          urls_to_fetch << url
        end
      end
      
      debug_lines << "Step 2 - Found #{cached_results.size} cached, fetching #{urls_to_fetch.size} from LLM"
      
      # Only call LLM for URLs not in cache
      if urls_to_fetch.any?
        pages_data = urls_to_fetch.map do |url|
          page = page_by_url[url.to_s]
          next unless page

          {
            url: url.to_s,
            existing_title: (page[:title] || extract_title_from_url(url)).to_s,
            existing_description: page[:description].to_s.strip[0..80]
          }
        end.compact

        if pages_data.any?
          prompt = <<~PROMPT
            Given this JSON array of page URLs, generate clean titles and LLM-optimized descriptions for each.
            For each page, provide:
            - title: clean, human-readable (fix casing, remove the product, company or website name from the title if it's present, remove extra words, make it concise)
            - description: write a NEW brief 1-2 sentence description optimized for LLMs (what the page is about, who it's for). Do not copy the existing meta description verbatim - rewrite it to be LLM-friendly and informative.
            
            Return ONLY valid JSON array. No markdown, no explanation.
            Format: [
              {"url": "url1", "title": "Clean Title", "description": "Brief description for LLMs."},
              {"url": "url2", "title": "Another Title", "description": "..."}
            ]

            Input (JSON array of pages with existing metadata as context):
            #{JSON.generate(pages_data)}
          PROMPT

          llm = create_llm_instance
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          response = llm.chat(messages: [{ role: "user", content: prompt }])
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          raw = response.chat_completion.to_s.strip
          raw = raw.gsub(/\A```(?:json)?\s*/, "").gsub(/\s*```\z/, "")
          results = JSON.parse(raw)
          debug_lines << "Step 2 - Enrichment latency: #{elapsed.round(2)} seconds"

          # Convert array to hash keyed by URL
          new_results = results.index_by { |item| item["url"].to_s }
          
          # Cache each new URL's title/description
          new_results.each do |url, item|
            cache_key = "llm_enrichment:#{url}"
            Rails.cache.write(cache_key, item, expires_in: 30.days)
          end
          
          cached_results.merge!(new_results)
          new_count = new_results.size
        else
          new_count = 0
        end
      else
        new_count = 0
      end
      
      cached_count = cached_results.size - new_count
      debug_lines << "Step 2 - Enrichment results: #{JSON.pretty_generate(cached_results)}"
      debug_lines << "Step 2 - Total enrichments: #{cached_results.size} (#{cached_count} cached, #{new_count} new)"
      cached_results
    rescue StandardError => e
      Rails.logger.warn("[Generator] LLM batch enrichment failed: #{e.message}")
      {}
    end

    def create_llm_instance
      if claude_model?
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

          # if Rails.env.development?
          #   line += " (depth: #{page[:depth]})"
          #   line += " (parent_url: #{page[:parent_url]})"
          # end
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
      return generate_description_via_llm if use_ai_description?
      return @homepage[:description] if @homepage[:description].to_s.strip != ""

      "No description available."
    end

    def use_ai_description?
      return true if @model in Run::LLM_MODELS
      return false if @model.blank?
      return false if @model.to_s.downcase.in?([Run::MODEL_NONE.downcase, "none"])

      llm_available?
    end

    def generate_description_via_llm
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

    # Turns a URL path into a short, human-readable label when there's no real page title
    # Examples:
    # https://example.com/about → "About"
    # https://example.com/docs/guides/getting-started → "Getting Started"
    # https://example.com/ → "Home"
    # https://example.com/contact-sales → "Contact Sales"
    # https://example.com/contact-sales/ → "Contact Sales"
    # https://example.com/contact-sales/ → "Contact Sales"
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