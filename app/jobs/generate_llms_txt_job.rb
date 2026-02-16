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

    generator = LlmsTxt::Generator.new(pages, failed_pages, run.model)
    llms_txt_content = generator.generate

    run.llms_txt = llms_txt_content
    run.save
    run.complete
  # TODO: Test This and Write Tests
  rescue Exception => e
    run&.fail
    raise e
  end
end
