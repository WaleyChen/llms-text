# frozen_string_literal: true

module Sites
  class RunsController < ApplicationController
    def index
      site = Site.find(params[:site_id])
      runs = site.runs.order(created_at: :desc)
      render json: runs
    end

    def create
      site = Site.find(params[:site_id])
      run = Run.create!(site_id: site.id, status: Run::STATUS_PENDING)
      GenerateLlmsTxtJob.perform_later(run.id)
      render json: run, status: :created
    end
  end
end
