# frozen_string_literal: true

class SiteChannel < ApplicationCable::Channel
  def subscribed
    site = Site.find_by(id: params[:site_id])
    return reject unless site
    stream_for site
  end

  def unsubscribed
    stop_all_streams
  end
end
