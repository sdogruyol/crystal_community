require "kemal"

# Basic environment setting (can be moved to a config layer later)
Kemal.config.env = ENV["KEMAL_ENV"]? || "development"

# Load database configuration
require "./config/database"

# Load models
require "./models/*"

# Load routes
require "./routes/web"

Kemal.run

