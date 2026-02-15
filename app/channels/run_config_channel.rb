# frozen_string_literal: true

class RunConfigChannel < ApplicationCable::Channel
  def subscribed
    run_config = RunConfig.find_by(id: params[:run_config_id])
    return reject unless run_config
    stream_for run_config
  end

  def unsubscribed
    stop_all_streams
  end
end
