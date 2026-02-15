class GenerateLlmsTxtJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = Run.find(run_id)
    run.start

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
    url = run.run_config.url
    url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)

    # Crawl the site (use run options if set)
    crawler = LlmsTxt::SiteCrawler.new(
      url,
      max_pages: run.respond_to?(:max_pages) ? run.max_pages : 20,
      max_depth: run.respond_to?(:max_depth) ? run.max_depth : 3
    )
    pages = crawler.crawl

    # Generate llms.txt content
    generator = LlmsTxt::Generator.new(pages)
    llms_txt_content = generator.generate

    run.llms_txt = llms_txt_content
    run.save
    run.complete
  rescue Faraday::Error, SocketError, URI::InvalidURIError => e
    run.fail
    raise e
  end
end
