class CrawlJob < ApplicationJob
  queue_as :default

  def perform(run_config_id)
    run_config = RunConfig.find(run_config_id)

    url = run_config.url
    url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)

    crawler = LlmsTxt::Crawler.new(
      url,
      max_pages: run_config.max_pages,
      max_depth: run_config.max_depth
    )
    result = crawler.crawl
    pages = result[:pages]
    failed_pages = result[:failed_pages]

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
