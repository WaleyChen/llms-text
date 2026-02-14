class AddRunLlmstxt < ActiveRecord::Migration[8.0]
  def change
    add_column :runs, :llms_txt, :text
  end
end
