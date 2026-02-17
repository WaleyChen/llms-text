ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# Encode DB URLs before any other app code so every process (web, worker, runner, rake) uses encoded passwords.
require_relative "../lib/database_url_encoding"
DatabaseUrlEncoding.apply_to_env!
