# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    respond_to do |format|
      format.html
      format.json { head :ok }
    end
  end
end
