get "/" { |env| CrystalCommunity::HomeController.index(env) }
get "/stats" { |env| CrystalCommunity::StatsController.index(env) }

# GitHub OAuth routes
get "/users/auth/github" { |env| CrystalCommunity::AuthController.github(env) }
get "/users/auth/github/callback" { |env| CrystalCommunity::AuthController.github_callback(env) }
