require "kemal"

class CrystalCommunity::HomeController
  # Home page action
  # Lists all developers (users) on the home page, similar to rubycommunity.org
  def self.index(env)
    page_title : String? = nil
    page_description : String? = nil
    request_url : String? = nil
    canonical_url : String? = nil
    og_url : String? = nil
    og_title : String? = nil
    og_description : String? = nil
    og_image : String? = nil
    twitter_url : String? = nil
    twitter_title : String? = nil
    twitter_description : String? = nil
    twitter_image : String? = nil

    total_developers = CrystalCommunity::DB::User.count
    developers = CrystalCommunity::DB::User.all

    render "src/views/home/index.ecr", "src/views/layouts/application.ecr"
  end
end
