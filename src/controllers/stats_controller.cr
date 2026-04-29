require "json"
require "kemal"
require "uri"

class CrystalCommunity::StatsController
  CHART_HISTORY_LIMIT = 90

  # GitHub topic pages list all languages; search narrows to Crystal repos only.
  def self.github_topic_url(topic : String) : String
    q = "topic:#{topic} language:crystal"
    "https://github.com/search?q=#{URI.encode_www_form(q)}&type=repositories"
  end

  def self.format_int_commas(n : Int64) : String
    return "0" if n == 0
    neg = n < 0
    v = n.abs
    parts = [] of String
    first_chunk = true
    while v > 0
      chunk = (v % 1000).to_s
      chunk = chunk.rjust(3, '0') unless first_chunk
      parts.unshift chunk
      first_chunk = false
      v //= 1000
    end
    (neg ? "-" : "") + parts.join(",")
  end

  def self.index(env)
    page_title = "Crystal Community: Crystal Ecosystem Stats"
    page_description = "Crystal Community — open source on GitHub, stars, recent activity, new repos, and top topics in the Crystal ecosystem. Updated as we scan public data."
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

    stats_chart_json = ""
    if github_stat_series.size >= 2
      stats_chart_json = {
        "labels" => github_stat_series.map { |s| s.collected_at.to_utc.to_s("%Y-%m-%d") },
        "repos"  => github_stat_series.map(&.repos_scanned),
        "stars"  => github_stat_series.map(&.total_stars),
      }.to_json
    end

    render "src/views/stats/index.ecr", "src/views/layouts/application.ecr"
  end
end
