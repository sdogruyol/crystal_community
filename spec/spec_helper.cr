require "spec"
require "spec-kemal"
require "spec-kemal/session"
require "dotenv"

# Load test environment variables
Dotenv.load ".env.test"

# Load the application config (this loads routes, controllers, etc.)
require "../src/config/config"

Spec.before_each do
  Kemal.config.env = "test"
  Kemal.config.setup
end