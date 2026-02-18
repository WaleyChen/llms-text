class GenerateLlmsTxtJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = Run.find(run_id)
    run.start
    run.broadcast_run_update

    # Get the crawl result from the cache
    crawl = Rails.cache.read(LlmsTxt::Crawler.run_crawl_cache_key(run))
    unless crawl
      run.fail
      raise "Crawl result expired or not found for run_config #{run.run_config_id}"
    end

    # Generate the llms.txt file
    generate_result = LlmsTxt::Generator.new(run, crawl[:pages], crawl[:failed_pages]).generate
    run.llms_txt = generate_result[:llms_txt]
    run.debug_logs = generate_result[:debug_logs]
    run.complete # Complete the run
    run.broadcast_run_update # Broadcast the run update to the client
  rescue StandardError => e
    run&.fail # Fail the run
    raise e
  end
end
