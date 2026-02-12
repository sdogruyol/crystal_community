require "kemal"
require "dotenv"
require "./config/config"

# Basic environment setting (can be moved to a config layer later)
Kemal.config.env = ENV["KEMAL_ENV"]? || "development"

# Load environment variables from .env.<env>, e.g. .env.development
Dotenv.load ".env.#{Kemal.config.env}"

# Load database configuration
require "./config/database"

# Load models
require "./models/*"

# Load routes
require "./routes/web"

Kemal.run

