require "db"
require "pg"
require "dotenv"

# Database configuration and connection
module CrystalCommunity::DB
  if CrystalCommunity::ENVIRONMENT == "production"
    Dotenv.load ".env.production"
  elsif CrystalCommunity::ENVIRONMENT == "staging"
    Dotenv.load ".env.staging"
  elsif CrystalCommunity::ENVIRONMENT == "test"
    Dotenv.load ".env.test"
  else
    Dotenv.load ".env.development"
  end

  # Get database URL from environment variable or use default
  URL  = ENV["DATABASE_URL"]

  # Create database connection
  def connection
    DB.open(url)
  end

  # Execute a block with a database connection
  def with_connection(&block)
    DB.open(url) do |db|
      yield db
    end
  end
end
