class RenameRunsSiteIdToRunConfigId < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :runs, :run_configs, column: :site_id
    rename_column :runs, :site_id, :run_config_id
    add_foreign_key :runs, :run_configs, column: :run_config_id
  end
end
