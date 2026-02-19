class RunsController < ApplicationController
  def llms_txt
    run = Run.find(params[:id])
    render plain: run.llms_txt, content_type: "text/plain"
  end

  def debug
    run = Run.find(params[:id])
    render plain: run.debug_logs, content_type: "text/plain"
  end
end
