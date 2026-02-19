# frozen_string_literal: true

require "set"
require "digest"

module LlmsTxt
  class Generator
    def initialize(run, pages, failed_pages)
      @homepage = pages.first
      @pages = pages.drop(1) # Exclude the homepage from the pages array
      @num_pages_displayed = 0
      @displayed_urls = Set.new
      @failed_pages = failed_pages
      @model = run.model
      @run = run
    end

    def generate
      generate_top_section()
      generate_url_sections()
      add_debug_info
    end

    private

    # Generate the top section/title and description of the llms.txt file
    def generate_top_section()
      lines = []
      if Run::LLM_MODELS.include?(@model)
        meta = generate_homepage_meta
        lines << "# #{meta[:title]}"
        lines << ""
        lines << "> #{meta[:description]}"
      else
        lines << "# #{@homepage[:title] || 'Untitled'}"
        lines << ""
        lines << "> #{@homepage[:description].to_s.strip.presence || 'No description available.'}"
      end
      lines << ""
      @run.append_llms_txt(lines)
    end

    def generate_url_sections()
      if @model == Run::MODEL_NONE
        generate_with_no_model()
      else
        generate_with_model(@model)
      end
    end

    def generate_with_no_model()
      lines = []
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
          lines << line
        end
        lines << ""
      end
      @run.append_llms_txt(lines)
    end

    def generate_with_model(model)
      all_urls = @pages.map { |p| p[:url].to_s }
      page_by_url = @pages.index_by { |p| p[:url].to_s }

      sections_result = nil
      enriched_urls_map = {}

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      grouping_thread = Thread.new do
        sections_result = group_urls_into_sections
      end

      enrichment_thread = Thread.new do
        enriched_urls_map = generate_titles_and_descriptions(all_urls, page_by_url)
      end

      grouping_thread.join
      enrichment_thread.join
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      @run.append_debug_logs("Step 3 - Total Latency: #{elapsed.round(2)} seconds")
      
      return generate_with_no_model() unless sections_result
      
      # Merge grouping with enriched titles/descriptions
      enriched_sections = {}
      sections_result.each do |section_name, urls|
        enriched_sections[section_name] = urls.map do |url|
          enriched_urls_map[url.to_s] || { "url" => url.to_s }
        end
      end
      
      render_llm_sections(enriched_sections)
      render_missing_pages()
    end

    def group_urls_into_sections
      pages_json = @pages.map do |p|
        title = p[:title] || extract_title_from_url(p[:url])
        desc = p[:description].to_s.strip
        desc = "#{desc[0..80]}..." if desc.length > 80
        { url: p[:url].to_s, title: title.to_s, description: desc }
      end
      pages_payload = JSON.generate(pages_json)

      cache_key = "#{@model}:grouping:#{Digest::MD5.hexdigest(pages_payload)}"
      cached = Rails.cache.read(cache_key)
      if cached
        @run.append_debug_logs("Step 1 - Grouping cache hit")
        return cached
      end

      @run.append_debug_logs("Step 1 - URLs passed for grouping: #{JSON.pretty_generate(pages_json)}")

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
        - Use an "Localized Pages" section for pages that are localized to a specific language.
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
      @run.append_debug_logs("Step 1 - Grouping result: #{JSON.pretty_generate(json)}")
      @run.append_debug_logs("Step 1 - Grouping latency: #{elapsed.round(2)} seconds")
      Rails.cache.write(cache_key, json, expires_in: 1.day)
      json
    rescue StandardError => e
      Rails.logger.warn("[Generator] LLM grouping failed: #{e.message}")
      @run.append_debug_logs("Step 1 - Grouping failed: #{e.message}")
      nil
    end


    def generate_titles_and_descriptions(urls, page_by_url)
      @run.append_debug_logs("Step 2 - Processing #{urls.size} URLs for title/description generation")

      cached_results = {}
      urls_to_fetch = []

      urls.each do |url|
        cache_key = "#{@model}:#{url}"
        cached = Rails.cache.read(cache_key)
        if cached
          cached_results[url.to_s] = cached
        else
          urls_to_fetch << url
        end
      end

      @run.append_debug_logs("Step 2 - Found #{cached_results.size} cached, fetching #{urls_to_fetch.size} from LLM")
      
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
          @run.append_debug_logs("Step 2 - Enrichment latency: #{elapsed.round(2)} seconds")

          # Convert array to hash keyed by URL
          new_results = results.index_by { |item| item["url"].to_s }
          
          # Cache each new URL's title/description
          new_results.each do |url, item|
            cache_key = "#{@model}:#{url}"
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
      @run.append_debug_logs("Step 2 - Enrichment results: #{JSON.pretty_generate(cached_results)}")
      @run.append_debug_logs("Step 2 - Total enrichments: #{cached_results.size} (#{cached_count} cached, #{new_count} new)")
      cached_results
    rescue StandardError => e
      Rails.logger.warn("[Generator] LLM batch enrichment failed: #{e.message}")
      {}
    end

    def create_llm_instance
      if @model.to_s == Run::MODEL_CLAUDE_SONNET_4_5
        Langchain::LLM::Anthropic.new(
          api_key: ENV["ANTHROPIC_API_KEY"],
          default_options: { chat_model: Run::MODEL_CLAUDE_SONNET_4_5, temperature: 0.2, max_tokens: 8192 }
        )
      elsif @model.to_s == Run::MODEL_GPT_5_2
        Langchain::LLM::OpenAI.new(
          api_key: ENV["OPENAI_API_KEY"],
          default_options: { chat_model: Run::MODEL_GPT_5_2, temperature: 0.2 }
        )
      else
        raise "Invalid model: #{@model}"
      end
    end

    def render_llm_sections(sections)
      lines = []
      page_by_url = @pages.index_by { |p| p[:url].to_s }

      sections.each do |section_name, items|
        next if items.blank?

        lines << "## #{section_name}"
        lines << ""
        items.each do |item|
          url_str = (item["url"] || item[:url]).to_s.strip
          page = page_by_url[url_str]
          next unless page

          @num_pages_displayed += 1
          @displayed_urls.add(page[:url])

          title = (item["title"] || item[:title]).to_s.strip.presence || page[:title] || extract_title_from_url(page[:url])
          description = (item["description"] || item[:description]).to_s.strip.presence || page[:description].to_s.strip
          line = "- [#{title}](#{page[:url]})"
          line += ": #{description}" if description.present?
          lines << line
        end
        lines << ""
      end
      @run.append_llms_txt(lines)
    end

    # Render pages not returned by the LLM
    def render_missing_pages()
      return if pages_not_displayed.empty?

      lines = []
      lines << "## Misc"
      lines << ""
      pages_not_displayed.each do |page|
        lines << "- [#{page[:title] || extract_title_from_url(page[:url])}](#{page[:url]}): #{page[:description].to_s.strip}"

        @num_pages_displayed += 1
        @displayed_urls.add(page[:url])
      end
      @run.append_llms_txt(lines)
    end

    # ------------------------------------------------------------

    def add_debug_info
      lines = [
        "## Total Pages: #{@pages.size}",
        "## Total Pages Displayed: #{@num_pages_displayed}",
        "## Total Failed Pages: #{@failed_pages.size}",
        "## Pages Not Displayed (#{pages_not_displayed.size})",
        *pages_not_displayed.map { |page| "- #{page[:url]} (depth: #{page[:depth]}, segments: #{path_segment_count(page[:url])})" },
        "## Failed Pages",
        @failed_pages.inspect,
      ]
      @run.append_debug_logs(lines)
    end

    def pages_not_displayed
      @pages.reject { |p| @displayed_urls.include?(p[:url]) }
    end

    def generate_homepage_meta
      cache_key = "#{@model}:homepage_meta:#{@homepage[:url]}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      llm = create_llm_instance
      content = build_description_context
      prompt = <<~PROMPT
        Given this website's homepage, generate a clean title and description for an llms.txt file.

        - title: A clean, concise title for the website (not the page). Remove taglines or marketing fluff.
        - description: A brief 2-4 sentence description of what this website/product is. Be concise and informative. Optimized for LLMs.

        Return ONLY valid JSON: {"title": "...", "description": "..."}

        Site title: #{@homepage[:title] || 'Untitled'}
        Content excerpt:
        #{content}
      PROMPT
      response = llm.chat(messages: [{ role: "user", content: prompt }])
      raw = response.chat_completion.to_s.strip
      raw = raw.gsub(/\A```(?:json)?\s*/, "").gsub(/\s*```\z/, "")
      json = JSON.parse(raw)
      result = { title: json["title"].to_s.strip, description: json["description"].to_s.strip }
      result[:title] = @homepage[:title] || "Untitled" if result[:title].blank?
      result[:description] = "No description available." if result[:description].blank?
      Rails.cache.write(cache_key, result, expires_in: 30.days)
      result
    rescue StandardError => e
      Rails.logger.warn("[Generator] LLM homepage meta failed: #{e.message}")
      { title: @homepage[:title] || "Untitled", description: "No description available." }
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