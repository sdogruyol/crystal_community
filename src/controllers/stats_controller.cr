require "kemal"

class CrystalCommunity::StatsController
  def self.index(env)
    page_title = "Crystal on GitHub — stats"
    page_description = "Public GitHub metrics for the Crystal ecosystem: repositories, unique owners, and unique committers."
    request_url = "/stats"
    canonical_url : String? = nil
    og_url : String? = nil
    og_title : String? = nil
    og_description : String? = nil
    og_image : String? = nil
    twitter_url : String? = nil
    twitter_title : String? = nil
    twitter_description : String? = nil
    twitter_image : String? = nil

    github_stat = CrystalCommunity::DB::GithubStat.latest

    render "src/views/stats/index.ecr", "src/views/layouts/application.ecr"
  end
end
