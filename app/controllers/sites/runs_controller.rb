# frozen_string_literal: true

module Sites
  class RunsController < ApplicationController
    def index
      site = Site.find(params[:site_id])
      runs = site.runs.order(created_at: :desc)
      render json: runs
    end
  end
end
