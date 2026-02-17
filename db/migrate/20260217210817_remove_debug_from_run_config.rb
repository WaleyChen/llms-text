class RemoveDebugFromRunConfig < ActiveRecord::Migration[8.0]
  def change
    remove_column :run_configs, :debug, :boolean
  end
end
