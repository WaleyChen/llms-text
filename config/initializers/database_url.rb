# frozen_string_literal: true

# Force production to use DATABASE_URL at runtime (e.g. Heroku).
# Patch the config before any connection so primary, queue, and cable all use the URL.
if Rails.env.production? && ENV["DATABASE_URL"].present?
  url = ENV["DATABASE_URL"]
  queue_url = ENV["QUEUE_DATABASE_URL"].presence || url
  cable_url = ENV["CABLE_DATABASE_URL"].presence || url

  Rails.application.config.before_initialize do
    next unless ActiveRecord::Base.respond_to?(:configurations)
    configs = ActiveRecord::Base.configurations
    next unless configs.respond_to?(:configurations_hash)
    hash = configs.configurations_hash
    prod = hash["production"]
    next unless prod.is_a?(Hash)
    { "primary" => url, "queue" => queue_url, "cable" => cable_url }.each do |role, role_url|
      next unless prod[role]
      base = prod[role].is_a?(Hash) ? prod[role] : prod[role].to_h
      prod[role] = base.merge("url" => role_url)
    end
  end
end
