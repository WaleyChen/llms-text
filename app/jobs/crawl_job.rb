class CrawlJob < ApplicationJob
    queue_as :default

    def perform(run_config_id) 
        run_config = RunConfig.find(run_config_id)
    
        # TODO: Think about valid and invalid URLs--return INVALID URLS to the user
        #     Accept:
        # pokemon.com
        # www.pokemon.com
        # https://pokemon.com
    
        # http://pokemon.com/docs
        # Normalize by:
        # If no scheme → prepend https://
        # Parse with a real URL parser (Addressable in Ruby)
        # Canonicalize host (downcase, strip trailing slash)
        # Reject private/internal IP ranges unless explicitly allowed
    
        # optionally:
        # enable multiple urls to be crawled at once
        url = run_config.url
        url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)
    
        # Crawl the site (use run options if set)
        crawler = LlmsTxt::Crawler.new(
          url,
          max_pages: run_config.max_pages,
          max_depth: run_config.max_depth
        )
        result = crawler.crawl
        pages = result[:pages]
        failed_pages = result[:failed_pages]
    
        if Rails.env.development?
          for i in 0..pages.size - 1
            page = pages[i]
            puts "page #{i} url: #{page[:url]}"
            puts "page #{i} parent_url: #{page[:parent_url]}"
            puts "page #{i} depth: #{page[:depth]}"
            puts "page #{i} title: #{page[:title]}"
            puts "page #{i} description: #{page[:description]}"
            puts "page #{i} associated_urls: #{page[:associated_urls]}"
            # puts "page #{i} content: #{page[:content]}"
            puts "--------------------------------"
          end
        end

        Rails.cache.write(
          "crawl:#{run_config.id}",
          { pages: pages, failed_pages: failed_pages },
          expires_in: 1.hour
        )

        run_config.runs.each do |run|
          GenerateLlmsTxtJob.perform_later(run.id)
        end
    end
end