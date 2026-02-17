class AddDebugLogsToRunConfig < ActiveRecord::Migration[8.0]
  def change
    add_column :runs, :debug_logs, :text
  end
end
