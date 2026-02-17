# Encode DB URLs before anything else so every process uses encoded passwords (Heroku DATABASE_URL can have special chars).
require_relative "../lib/database_url_encoding"
DatabaseUrlEncoding.apply_to_env!

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
