class CreateLlmTxts < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_txts do |t|
      t.timestamps
    end
  end
end
