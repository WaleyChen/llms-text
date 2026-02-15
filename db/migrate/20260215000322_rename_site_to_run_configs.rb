class RenameSiteToRunConfigs < ActiveRecord::Migration[8.0]
  def change
    rename_table :sites, :run_configs
  end
end
