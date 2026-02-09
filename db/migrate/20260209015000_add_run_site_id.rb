class AddRunSiteId < ActiveRecord::Migration[8.0]
  def change
    add_column :runs, :site_id, :integer
    add_foreign_key :runs, :sites
  end
end
