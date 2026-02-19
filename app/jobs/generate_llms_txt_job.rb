class GenerateLlmsTxtJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = Run.find(run_id)
    run.run_config.start_generating
    run.start

    # Get the crawl result from the cache
    crawl = Rails.cache.read(LlmsTxt::Crawler.run_crawl_cache_key(run))
    unless crawl
      run.run_config.fail
      run.fail
      raise "Crawl result expired or not found for run_config #{run.run_config_id}"
    end

    LlmsTxt::Generator.new(run, crawl[:pages], crawl[:failed_pages]).generate
    run.complete
    run.run_config.complete
  rescue StandardError => e
    run&.fail # Fail the run
    raise e
  end
end
