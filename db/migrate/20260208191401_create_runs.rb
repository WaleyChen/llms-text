class CreateRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :runs do |t|
      t.timestamps
    end
  end
end
