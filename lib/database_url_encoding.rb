# frozen_string_literal: true

# Encode password in Postgres URL so special characters (@, :, /, #, etc.) don't
# break parsing. Heroku sets DATABASE_URL and Rails merges it into config; encoding
# at boot ensures every connection (primary, queue, cache, cable) gets the same URL.
module DatabaseUrlEncoding
  UNRESERVED = /\A[A-Za-z0-9\-._~]\z/

  def self.encode_password_in_url(raw_url)
    return raw_url if raw_url.to_s.strip.empty?
    return raw_url unless raw_url.include?("://") && raw_url.include?("@")
    scheme, rest = raw_url.split("://", 2)
    userinfo, host_part = rest.split("@", 2)
    return raw_url if (userinfo || "").strip.empty? || (host_part || "").strip.empty?
    user, password = userinfo.split(":", 2)
    return raw_url if password.nil?
    enc = password.each_char.map { |c| c.match?(UNRESERVED) ? c : "%%%02X" % c.ord }.join
    "#{scheme}://#{user}:#{enc}@#{host_part}"
  end

  def self.apply_to_env!
    # Use plain Ruby (no ActiveSupport) so this runs when Rake loads app before Rails.
    # Also set *_ENCODED so database.yml can use them if DATABASE_URL is overwritten later (e.g. by Heroku).
    if (url = ENV["DATABASE_URL"]) && !url.empty?
      encoded = encode_password_in_url(url)
      ENV["DATABASE_URL"] = encoded
      ENV["DATABASE_URL_ENCODED"] = encoded
    end
    if (url = ENV["CACHE_DATABASE_URL"]) && !url.empty?
      encoded = encode_password_in_url(url)
      ENV["CACHE_DATABASE_URL"] = encoded
      ENV["CACHE_DATABASE_URL_ENCODED"] = encoded
    end
    if (url = ENV["QUEUE_DATABASE_URL"]) && !url.empty?
      encoded = encode_password_in_url(url)
      ENV["QUEUE_DATABASE_URL"] = encoded
      ENV["QUEUE_DATABASE_URL_ENCODED"] = encoded
    end
    if (url = ENV["CABLE_DATABASE_URL"]) && !url.empty?
      encoded = encode_password_in_url(url)
      ENV["CABLE_DATABASE_URL"] = encoded
      ENV["CABLE_DATABASE_URL_ENCODED"] = encoded
    end
  end
end
