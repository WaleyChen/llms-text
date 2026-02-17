# frozen_string_literal: true

module RunConfigs
  class RunsController < ApplicationController
    def index
      run_config = RunConfig.find(params[:run_config_id])
      runs = run_config.runs.order(created_at: :desc)
      render json: runs
    end
  end
end
