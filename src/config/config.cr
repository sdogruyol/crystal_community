require "kemal"
require "kemal-session"
require "dotenv"

require "./constants"
require "./database"

# Basic environment setting (can be moved to a config layer later)
Kemal.config.env = ENV["CRYSTAL_COMMUNITY_ENV"]? || "development"


# Configure session (after loading env vars)
Kemal::Session.config do |config|
  config.secret = ENV["SESSION_SECRET"]? || "your-secret-key-change-this-in-production"
  config.gc_interval = 2.minutes
end

# Load models
require "../models/*"

# Load routes
require "../routes/web"
