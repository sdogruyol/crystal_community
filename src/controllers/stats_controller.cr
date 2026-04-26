require "kemal"

class CrystalCommunity::StatsController
  CHART_HISTORY_LIMIT = 90

  def self.index(env)
    page_title = "Crystal on GitHub — stats"
    page_description = "Public GitHub metrics for the Crystal ecosystem: repositories, activity, stars, owners, and topics over time."
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

    db = CrystalCommunity::DB::GithubStat
    github_stat = db.latest
    github_stat_series = db.recent_chronological(CHART_HISTORY_LIMIT)

    chart_line_repos = ""
    chart_line_pushed = ""
    chart_line_created = ""
    chart_line_stars = ""
    if github_stat_series.size >= 2
      chart_line_repos = db.chart_line_points(github_stat_series) { |s| s.repos_scanned.to_f64 }
      chart_line_pushed = db.chart_line_points(github_stat_series) { |s| s.repos_pushed_last_30d.to_f64 }
      chart_line_created = db.chart_line_points(github_stat_series) { |s| s.repos_created_last_30d.to_f64 }
      chart_line_stars = db.chart_line_points(github_stat_series) { |s| s.total_stars.to_f64 }
    end

    render "src/views/stats/index.ecr", "src/views/layouts/application.ecr"
  end
end
