require "db"
require "pg"

# Database configuration and connection
module Database
  extend self

  # Get database URL from environment variable or use default
  def url : String
    ENV["DATABASE_URL"]? || "postgres://localhost/crystal_community_#{Kemal.config.env}"
  end

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
