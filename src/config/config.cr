require "kemal"
require "kemal-session"
require "dotenv"

if CrystalCommunity::ENVIRONMENT == "production"
  Dotenv.load ".env.production"
elsif CrystalCommunity::ENVIRONMENT == "staging"
  Dotenv.load ".env.staging"
elsif CrystalCommunity::ENVIRONMENT == "test"
  Dotenv.load ".env.test"
else
  Dotenv.load ".env.development"
end

require "./constants"
require "./database"

# Basic environment setting (can be moved to a config layer later)
Kemal.config.env = ENV["CRYSTAL_COMMUNITY_ENV"]? || "development"
Kemal.config.port = ENV["CRYSTAL_COMMUNITY_PORT"]?.try(&.to_i) || 3000

# Configure session (after loading env vars)
Kemal::Session.config do |config|
  config.secret = ENV["SESSION_SECRET"]? || "your-secret-key-change-this-in-production"
  config.gc_interval = 2.minutes
end

require "../models/*"
require "../controllers/*"
require "../services/*"

require "../routes/*"
