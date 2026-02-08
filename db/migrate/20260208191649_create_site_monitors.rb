class CreateSiteMonitors < ActiveRecord::Migration[8.0]
  def change
    create_table :site_monitors do |t|
      t.timestamps
    end
  end
end
