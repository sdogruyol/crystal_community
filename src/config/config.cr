require "kemal"
require "dotenv"

require "./constants"
require "./database"

# Basic environment setting (can be moved to a config layer later)
Kemal.config.env = ENV["CRYSTAL_COMMUNITY_ENV"]? || "development"

# Load environment variables from .env.<env>, e.g. .env.development
Dotenv.load ".env.#{CrystalCommunity::ENVIRONMENT}"

# Load models
require "../models/*"

# Load routes
require "../routes/web"

