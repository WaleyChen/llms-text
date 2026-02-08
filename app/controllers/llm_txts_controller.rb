# frozen_string_literal: true

class LlmTxtsController < ApplicationController
  def create
    # No persistence for now — just receive the POST
    redirect_to root_path
  end
end
