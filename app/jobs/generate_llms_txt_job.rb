class GenerateLlmsTxtJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = Run.find(run_id)
    run.start
    run.broadcast_run_update

    crawl = Rails.cache.read(LlmsTxt::Crawler.run_crawl_cache_key(run))
    unless crawl
      run.fail
      raise "Crawl result expired or not found for run_config #{run.run_config_id}"
    end

    pages = crawl[:pages] || crawl["pages"] || []
    failed_pages = crawl[:failed_pages] || crawl["failed_pages"] || []

    generator = LlmsTxt::Generator.new(run, pages, failed_pages)
    result = generator.generate
    run.llms_txt = result[:llms_txt]
    run.debug_logs = result[:debug_logs]
    run.complete
    run.broadcast_run_update
  rescue StandardError => e
    run&.fail
    raise e
  end
end
