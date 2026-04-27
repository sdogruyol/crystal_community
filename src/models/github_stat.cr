require "json"

module CrystalCommunity::DB
  struct GithubStat
    include ::DB::Serializable
    property id : Int64?
    property since : Time
    property repos_scanned : Int32
    property unique_owners : Int32
    property unique_committers : Int32
    property collected_at : Time
    property repos_pushed_last_30d : Int32
    property repos_created_last_30d : Int32
    property total_stars : Int64
    property stars_bucket_0 : Int32
    property stars_bucket_1_10 : Int32
    property stars_bucket_11_100 : Int32
    property stars_bucket_101_1000 : Int32
    property stars_bucket_1001_plus : Int32
    property repos_owner_user : Int32
    property repos_owner_org : Int32
    property top_topics_json : String

    SELECT_ROW = "id, since, repos_scanned, unique_owners, unique_committers, collected_at, repos_pushed_last_30d, repos_created_last_30d, total_stars, stars_bucket_0, stars_bucket_1_10, stars_bucket_11_100, stars_bucket_101_1000, stars_bucket_1001_plus, repos_owner_user, repos_owner_org, top_topics_json"

    def top_topics : Array({String, Int32})
      return [] of {String, Int32} if top_topics_json.empty?
      JSON.parse(top_topics_json).as_a.map do |o|
        {o["topic"].as_s, o["count"].as_i}
      end
    rescue
      [] of {String, Int32}
    end

    def self.insert!(
      since : Time,
      repos_scanned : Int32,
      unique_owners : Int32,
      unique_committers : Int32,
      repos_pushed_last_30d : Int32,
      repos_created_last_30d : Int32,
      total_stars : Int64,
      stars_bucket_0 : Int32,
      stars_bucket_1_10 : Int32,
      stars_bucket_11_100 : Int32,
      stars_bucket_101_1000 : Int32,
      stars_bucket_1001_plus : Int32,
      repos_owner_user : Int32,
      repos_owner_org : Int32,
      top_topics_json : String,
      collected_at : Time = Time.utc
    ) : GithubStat
      SQL.query_one(
        <<-SQL,
        INSERT INTO github_stats (
          since, repos_scanned, unique_owners, unique_committers, collected_at,
          repos_pushed_last_30d, repos_created_last_30d, total_stars,
          stars_bucket_0, stars_bucket_1_10, stars_bucket_11_100, stars_bucket_101_1000, stars_bucket_1001_plus,
          repos_owner_user, repos_owner_org, top_topics_json
        ) VALUES (
          $1, $2, $3, $4, $5,
          $6, $7, $8,
          $9, $10, $11, $12, $13,
          $14, $15, $16
        )
        RETURNING #{SELECT_ROW}
        SQL
        since, repos_scanned, unique_owners, unique_committers, collected_at,
        repos_pushed_last_30d, repos_created_last_30d, total_stars,
        stars_bucket_0, stars_bucket_1_10, stars_bucket_11_100, stars_bucket_101_1000, stars_bucket_1001_plus,
        repos_owner_user, repos_owner_org, top_topics_json,
        as: GithubStat
      )
    end

    def self.latest : GithubStat?
      SQL.query_one?(
        "SELECT #{SELECT_ROW} FROM github_stats ORDER BY collected_at DESC LIMIT 1",
        as: GithubStat
      )
    end

    # Oldest-first, for charts (last `limit` runs by time).
    def self.recent_chronological(limit : Int32 = 120) : Array(GithubStat)
      rows = SQL.query_all(
        "SELECT #{SELECT_ROW} FROM github_stats ORDER BY collected_at DESC LIMIT $1",
        limit,
        as: GithubStat
      )
      rows.reverse!
      rows
    end
  end
end
