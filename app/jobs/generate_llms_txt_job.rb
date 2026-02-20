class GenerateLlmsTxtJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = Run.find(run_id)
    ActiveRecord::Base.transaction do
      run.run_config.start_generating
      run.start
    end

    # Get the crawl result from the cache
    crawl = Rails.cache.read(LlmsTxt::Crawler.run_crawl_cache_key(run))
    unless crawl
      ActiveRecord::Base.transaction do
        run.run_config.fail
        run.fail
      end
      raise "Crawl result expired or not found for run_config #{run.run_config_id}"
    end

    LlmsTxt::Generator.new(run, crawl[:pages], crawl[:failed_pages]).generate
    ActiveRecord::Base.transaction do
      run.complete
      run.run_config.complete
    end
  rescue StandardError => e
    ActiveRecord::Base.transaction do
      run.append_debug_logs("GenerateLlmsTxtJob Error: #{e.message}") if run
      run&.fail
      run.run_config.fail if run
    end
    raise e
  end
end
