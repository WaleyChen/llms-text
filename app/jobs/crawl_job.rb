class CrawlJob < ApplicationJob
  queue_as :default

  def perform(run_config_id)
    run_config = RunConfig.find(run_config_id)
    run_config.start_crawl
    url = run_config.url

    crawler = LlmsTxt::Crawler.new(
      url,
      max_pages: run_config.max_pages,
      max_depth: run_config.max_depth,
      run_config: run_config
    )
    result = crawler.crawl
    Rails.logger.info("[CrawlJob] Result: #{result.inspect.pretty_inspect}")

    if result[:error]
      run_config.fail_all_runs(result[:error])
      return
    end

    run_config.runs.each do |run|
      GenerateLlmsTxtJob.perform_later(run.id)
    end
  rescue StandardError => e
    Rails.logger.error("[CrawlJob] Failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    run_config = RunConfig.find_by(id: run_config_id)
    run_config.fail_all_runs(e.message) if run_config
    raise e
  end
end
