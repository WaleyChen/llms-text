class GenerateLlmsTxtJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = Run.find(run_id)
    run.start

    url = run.site.url

    body = LlmsTxt::Crawler.get(url).body
    doc = Nokogiri::HTML(body)
    extracted = LlmsTxt::PageExtractor.new(doc, url).to_h
    puts extracted.inspect
    # extracted => { title:, llms_txt_url:, associated_urls: }

    run.complete
  rescue Faraday::Error, SocketError, URI::InvalidURIError => e
    run.fail
    raise e
  end
end
