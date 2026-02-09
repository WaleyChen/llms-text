class GenerateLlmsTxtJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    begin
      run = Run.find(run_id)
      run.start
      run.complete
    rescue => e
      run.fail
      raise e
    end
  end
end
