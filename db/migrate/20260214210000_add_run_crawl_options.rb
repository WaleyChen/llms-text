# frozen_string_literal: true

class AddRunCrawlOptions < ActiveRecord::Migration[8.0]
  def change
    add_column :runs, :max_pages, :integer
    add_column :runs, :max_depth, :integer
    add_column :runs, :model, :string
  end
end
