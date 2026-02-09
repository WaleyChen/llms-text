# frozen_string_literal: true

# Force production primary connection to use DATABASE_URL at runtime (e.g. Heroku).
# Runs first so the default connection never uses socket. Cable/queue use url from database.yml.
if Rails.env.production? && ENV["DATABASE_URL"].present?
  ActiveRecord::Base.establish_connection(ENV["DATABASE_URL"])
end
