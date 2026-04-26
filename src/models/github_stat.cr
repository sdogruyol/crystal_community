module CrystalCommunity::DB
  struct GithubStat
    include ::DB::Serializable
    property id : Int64?
    property since : Time
    property repos_scanned : Int32
    property unique_owners : Int32
    property unique_committers : Int32
    property collected_at : Time

    def self.insert!(
      since : Time,
      repos_scanned : Int32,
      unique_owners : Int32,
      unique_committers : Int32,
      collected_at : Time = Time.utc
    ) : GithubStat
      SQL.query_one(
        "INSERT INTO github_stats (since, repos_scanned, unique_owners, unique_committers, collected_at) VALUES ($1, $2, $3, $4, $5) RETURNING id, since, repos_scanned, unique_owners, unique_committers, collected_at",
        since, repos_scanned, unique_owners, unique_committers, collected_at,
        as: GithubStat
      )
    end

    def self.latest : GithubStat?
      SQL.query_one?(
        "SELECT id, since, repos_scanned, unique_owners, unique_committers, collected_at FROM github_stats ORDER BY collected_at DESC LIMIT 1",
        as: GithubStat
      )
    end
  end
end
