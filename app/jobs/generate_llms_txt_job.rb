class GenerateLlmsTxtJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = Run.find(run_id)
    run.start

    crawl = Rails.cache.read("crawl:#{run.run_config_id}")
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
    run.save
    run.complete
  # TODO: Test This and Write Tests
  rescue StandardError => e
    run&.fail
    raise e
  end
end
