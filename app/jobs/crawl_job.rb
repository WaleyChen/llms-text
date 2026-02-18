class CrawlJob < ApplicationJob
  queue_as :default

  def perform(run_config_id)
    run_config = RunConfig.find(run_config_id)
    url = run_config.url

    crawler = LlmsTxt::Crawler.new(
      url,
      max_pages: run_config.max_pages,
      max_depth: run_config.max_depth
    )
    result = crawler.crawl

    if result[:error]
      run_config.runs.each do |run|
        run.update!(status: Run::STATUS_FAILED, error: result[:error])
      end
      return
    end

    run_config.runs.each do |run|
      GenerateLlmsTxtJob.perform_later(run.id)
    end
  end
end
