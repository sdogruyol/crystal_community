require "json"
require "../config/config"

module CrystalCommunity::Seeders
  class FakeGithubStatGenerator
    DEFAULT_COUNT = 30

    TOPIC_POOL = %w[
      crystal crystal-lang crystal-language cli kemal lucky web api database
      redis docker http json framework testing shards shard postgresql orm
      terminal parser discord linux security library bot markdown server
    ]

    # Inserts fake `github_stats` rows with `collected_at` stepped back one day per row
    # (newest first in DB order for charts). `repos_scanned` and `total_stars` rise monotonically
    # as `collected_at` moves forward (oldest day = smallest, today = largest).
    # Star buckets sum to `repos_scanned`; user + org repo counts equal `repos_scanned`.
    def run(count : Int32 = DEFAULT_COUNT)
      window = CrystalCommunity::GitHubCrystalStatsCollector::STATS_ROLLING_WINDOW
      min_repos = rand(3_800..5_500)
      max_repos = rand(min_repos + 2_500..min_repos + 7_000)
      min_stars = rand(45_000_i64..95_000_i64)
      max_stars = rand(min_stars + 35_000_i64..min_stars + 130_000_i64)
      span = count > 1 ? count - 1 : 1

      count.times do |i|
        collected = Time.utc - i.days
        since = collected - window
        t = count > 1 ? (count - 1 - i) : 0
        repos = min_repos + (t * (max_repos - min_repos)) // span
        total_stars = min_stars + (t.to_i64 * (max_stars - min_stars)) // span
        b0, b1, b2, b3, b4 = star_buckets_summing_to(repos)
        owners_lo = Math.max(1, repos // 4)
        owners_hi = Math.max(owners_lo, repos // 2)

        user_part = rand((repos * 0.72).to_i..(repos * 0.92).to_i).clamp(0, repos)
        org_part = repos - user_part

        CrystalCommunity::DB::GithubStat.insert!(
          since: since,
          repos_scanned: repos,
          unique_owners: rand(owners_lo..owners_hi),
          unique_committers: rand < 0.75 ? 0 : rand(1..120),
          repos_pushed_last_30d: rand(Math.max(1, repos // 25)..Math.max(1, repos // 3)),
          repos_created_last_30d: rand(Math.max(1, repos // 40)..Math.max(1, repos // 8)),
          total_stars: total_stars,
          stars_bucket_0: b0,
          stars_bucket_1_10: b1,
          stars_bucket_11_100: b2,
          stars_bucket_101_1000: b3,
          stars_bucket_1001_plus: b4,
          repos_owner_user: user_part,
          repos_owner_org: org_part,
          top_topics_json: fake_top_topics_json,
          collected_at: collected
        )
      end
    end

    private def star_buckets_summing_to(repos : Int32) : Tuple(Int32, Int32, Int32, Int32, Int32)
      weights = Array.new(5) { rand(0.02..1.0) }
      sum_w = weights.sum
      parts = weights.map { |w| (w / sum_w * repos).to_i }
      delta = repos - parts.sum
      parts[0] += delta
      {parts[0], parts[1], parts[2], parts[3], parts[4]}
    end

    private def fake_top_topics_json : String
      n = rand(8..Math.min(20, TOPIC_POOL.size))
      labels = TOPIC_POOL.shuffle.first(n)
      hi = rand(400..2_500)
      counts = Array.new(n) { |i| Math.max(1, hi - i * rand(15..80)) }.sort.reverse
      pairs = labels.zip(counts)

      String.build do |io|
        JSON.build(io) do |jb|
          jb.array do
            pairs.each do |(topic, c)|
              jb.object do
                jb.field "topic", topic
                jb.field "count", c
              end
            end
          end
        end
      end
    end
  end
end

CrystalCommunity::Seeders::FakeGithubStatGenerator.new.run
