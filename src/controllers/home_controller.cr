require "kemal"

class CrystalCommunity::HomeController
  # Home page action
  def self.index(env)
    # In the future data will come from the DB; for now we use dummy values
    total_developers = 161
    trending_developers = [] of String

    # Render view
    render "src/views/home/index.ecr", "src/views/layouts/application.ecr"
  end
end
