class GenerateLlmsTxtJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = Run.find(run_id)
    run.start

    url = run.site.url

    body = LlmsTxt::Crawler.get(url).body
    doc = Nokogiri::HTML(body)

    run.complete
  rescue Faraday::Error, SocketError, URI::InvalidURIError => e
    run.fail
    raise e
  end
end
