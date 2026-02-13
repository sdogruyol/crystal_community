require "spec"
require "spec-kemal"
require "spec-kemal/session"
require "dotenv"

# In CI, environment variables are set directly, so skip loading .env.test
unless ENV["CI"]?
  Dotenv.load ".env.test"
end

# Load the application config (this loads routes, controllers, etc.)
require "../src/config/config"

Spec.before_each do
  Kemal.config.env = "test"
  Kemal.config.setup
end