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
      attrs = { site_id: site.id, status: Run::STATUS_PENDING }
      attrs[:max_pages] = run_params[:max_pages].to_i if run_params[:max_pages].present?
      attrs[:max_depth] = run_params[:max_depth].to_i if run_params[:max_depth].present?
      attrs[:model] = run_params[:model] if run_params[:model].present?
      run = Run.create!(attrs)
      GenerateLlmsTxtJob.perform_later(run.id)
      render json: run, status: :created
    end

    private

    def run_params
      params.permit(:max_pages, :max_depth, :model).to_h.symbolize_keys
    end
  end
end
