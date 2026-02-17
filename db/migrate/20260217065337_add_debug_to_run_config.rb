class AddDebugToRunConfig < ActiveRecord::Migration[8.0]
  def change
    add_column :run_configs, :debug, :boolean, default: false, null: true
  end
end
