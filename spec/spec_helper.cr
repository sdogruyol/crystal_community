require "spec"
require "spec-kemal"
require "spec-kemal/session"
require "dotenv"

# Load test environment variables from .env.test if it exists
# In CI, environment variables are set directly, so this file may not exist
if File.exists?(".env.test")
  Dotenv.load ".env.test"
end

# Load the application config (this loads routes, controllers, etc.)
require "../src/config/config"

Spec.before_each do
  Kemal.config.env = "test"
  Kemal.config.setup
end