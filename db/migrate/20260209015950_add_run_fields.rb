class AddRunFields < ActiveRecord::Migration[8.0]
  def change
    add_column :runs, :started_at, :datetime
    add_column :runs, :finished_at, :datetime
    add_column :runs, :status, :string
    add_column :runs, :phase, :string
  end
end
