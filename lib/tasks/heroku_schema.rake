# frozen_string_literal: true

# Load queue/cable schemas into the DATABASE_URL database (Heroku single-DB).
# Use when db:schema:load:queue / db:schema:load:cable fail due to config.
# Run: heroku run 'DISABLE_DATABASE_ENVIRONMENT_CHECK=1 rails db:schema:load:queue:heroku'
#      heroku run 'DISABLE_DATABASE_ENVIRONMENT_CHECK=1 rails db:schema:load:cable:heroku'
namespace :db do
  namespace :schema do
    task "load:queue:heroku" => :environment do
      next abort("DATABASE_URL not set") unless ENV["DATABASE_URL"].present?
      ActiveRecord::Base.establish_connection(ENV["DATABASE_URL"])
      load Rails.root.join("db", "queue_schema.rb")
      puts "Loaded queue schema into current database."
    end

    task "load:cable:heroku" => :environment do
      next abort("DATABASE_URL not set") unless ENV["DATABASE_URL"].present?
      ActiveRecord::Base.establish_connection(ENV["DATABASE_URL"])
      load Rails.root.join("db", "cable_schema.rb")
      puts "Loaded cable schema into current database."
    end
  end
end
