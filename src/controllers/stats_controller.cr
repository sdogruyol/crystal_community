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

  # Matches star buckets in github_crystal_stats_collector (labels use en dash U+2013).
  def self.github_star_bucket_search_url(star_band_label : String) : String
    q = case star_band_label
        when "0"
          "language:crystal stars:0..0"
        when "1\u201310"
          "language:crystal stars:1..10"
        when "11\u2013100"
          "language:crystal stars:11..100"
        when "101\u20131000"
          "language:crystal stars:101..1000"
        when "1001+"
          "language:crystal stars:>1000"
        else
          "language:crystal"
        end
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

  # Screen-reader text for Chart.js canvases (role="img") above scan history.
  def self.chart_line_aria_label(metric_name : String, labels : Array(String), values : Array(Int64)) : String
    return "" if labels.size < 2 || values.size < 2
    first = values.first.not_nil!
    last = values.last.not_nil!
    trend = if last > first
              "rising"
            elsif last < first
              "falling"
            else
              "flat"
            end
    "Line chart of #{metric_name} across #{labels.size} GitHub catalog scans from #{labels.first} to #{labels.last}: #{format_int_commas(first)} at the earliest scan, #{format_int_commas(last)} at the latest, overall #{trend}."
  end

  def self.chart_line_aria_description(metric_name : String, labels : Array(String), values : Array(Int64)) : String
    return "" if labels.empty? || values.empty?
    points = [] of String
    labels.each_with_index do |label, i|
      v = values[i]?
      next unless v
      points << "#{label}: #{format_int_commas(v)}"
    end
    "#{metric_name} by scan date (oldest to newest): #{points.join("; ")}."
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
    chart_labels = [] of String
    chart_repos_values = [] of Int64
    chart_stars_values = [] of Int64
    chart_repos_aria_label = ""
    chart_stars_aria_label = ""
    chart_repos_aria_desc = ""
    chart_stars_aria_desc = ""

    if github_stat_series.size >= 2
      chart_labels = github_stat_series.map { |s| s.collected_at.to_utc.to_s("%Y-%m-%d") }
      chart_repos_values = github_stat_series.map { |s| s.repos_scanned.to_i64 }
      chart_stars_values = github_stat_series.map(&.total_stars)
      stats_chart_json = {
        "labels" => chart_labels,
        "repos"  => chart_repos_values,
        "stars"  => chart_stars_values,
      }.to_json
      chart_repos_aria_label = chart_line_aria_label(
        "Crystal repositories scanned",
        chart_labels,
        chart_repos_values
      )
      chart_stars_aria_label = chart_line_aria_label(
        "total GitHub stars summed across the public Crystal repository catalog",
        chart_labels,
        chart_stars_values
      )
      chart_repos_aria_desc = chart_line_aria_description(
        "Repositories scanned",
        chart_labels,
        chart_repos_values
      )
      chart_stars_aria_desc = chart_line_aria_description(
        "Total stars",
        chart_labels,
        chart_stars_values
      )
    end

    render "src/views/stats/index.ecr", "src/views/layouts/application.ecr"
  end
end
