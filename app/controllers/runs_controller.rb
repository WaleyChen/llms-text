class RunsController < ApplicationController
  def llms_txt
    run = Run.find(params[:id])
    if run.llms_txt.blank?
      head :not_found
      return
    end
    render plain: run.llms_txt, content_type: "text/plain"
  end

  def debug
    run = Run.find(params[:id])
    if run.debug_logs.blank?
      head :not_found
      return
    end
    render plain: run.debug_logs, content_type: "text/plain"
  end
end
