class AddConfigFieldsToRunConfig < ActiveRecord::Migration[8.0]
  def change
    add_column :run_configs, :max_pages, :integer
    add_column :run_configs, :max_depth, :integer
    add_column :run_configs, :model, :string
  end
end
