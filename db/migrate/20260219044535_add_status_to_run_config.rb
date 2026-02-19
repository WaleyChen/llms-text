class AddStatusToRunConfig < ActiveRecord::Migration[8.0]
  def change
    add_column :run_configs, :status, :string
  end
end
