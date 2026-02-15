# frozen_string_literal: true

module RunConfigs
  class RunsController < ApplicationController
    def index
      run_config = RunConfig.find(params[:run_config_id])
      runs = run_config.runs.order(created_at: :desc)
      render json: runs
    end

    def create
      run_config = RunConfig.find(params[:run_config_id])
      attrs = { run_config_id: run_config.id, status: Run::STATUS_PENDING }
      attrs[:model] = run_params[:model] if run_params[:model].present?
      run = Run.create!(attrs)
      GenerateLlmsTxtJob.perform_later(run.id, run.model || run_config.model)
      render json: run, status: :created
    end

    private

    def run_params
      params.permit(:run_config_id, :max_pages, :max_depth, :model).to_h.symbolize_keys
    end
  end
end
