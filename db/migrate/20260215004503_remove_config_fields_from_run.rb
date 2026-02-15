class RemoveConfigFieldsFromRun < ActiveRecord::Migration[8.0]
  def change
    remove_column :runs, :max_pages, :integer
    remove_column :runs, :max_depth, :integer
  end
end
