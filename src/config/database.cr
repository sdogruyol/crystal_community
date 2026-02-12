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
  URL = ENV["DATABASE_URL"]

  SQL = begin
    masked_uri = URI.parse(URL)
    if (user = masked_uri.user) && !user.blank?
      masked_uri.user = "REDACTED"
    end
    if (password = masked_uri.password) && !password.blank?
      masked_uri.password = "REDACTED"
    end
    Log.info(&.emit("Connecting to #{masked_uri}", event: "db_connect"))
    ::DB.open(URL)
  end

  SQL.query_one(
    "SELECT count(1)",
    as: Int64
  )
end
