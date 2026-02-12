require "kemal"

class CrystalCommunity::HomeController
  # Home page action
  # Lists all developers (users) on the home page, similar to rubycommunity.org
  def self.index(env)
    total_developers = CrystalCommunity::DB::User.count
    developers = CrystalCommunity::DB::User.all

    render "src/views/home/index.ecr", "src/views/layouts/application.ecr"
  end
end
