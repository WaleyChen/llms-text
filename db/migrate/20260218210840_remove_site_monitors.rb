class RemoveSiteMonitors < ActiveRecord::Migration[8.0]
  def change
    drop_table :site_monitors, if_exists: true
  end
end
