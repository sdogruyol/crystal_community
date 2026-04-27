require "http/client"
require "json"
require "uri"
require "set"
require "time"

module CrystalCommunity
  # Collects public GitHub stats for Crystal repositories via the REST API.
  # Intended for scheduled runs (e.g. hourly cron). Counts only public data.
  #
  # - Excludes forks via repo search query `fork:false`.
  # - Repo discovery subdivides Search by `stars` (then `pushed` if needed) to approach full universe past the 1000-results/query cap.
  # - Excludes bots by login suffix `"[bot]"` for unique-owner counts only.
  # - Rolling 30-day window (UTC) from collection time for pushed/created repo counts.
  # - Star totals and buckets, owner User vs Organization, and top topics come from Search `items` (no per-repo GETs).
  # - No file or DB cache: every run loads the repo list from Search.
  class GitHubCrystalStatsCollector
    class Error < Exception
    end

    STATS_ROLLING_WINDOW = 30.days

    private struct CrystalRepoHit
      getter full_name : String
      getter owner_login : String
      getter owner_type : String
      getter created_at : Time
      getter pushed_at : Time
      getter stargazers_count : Int32
      getter topics : Array(String)

      def initialize(
        @full_name : String,
        @owner_login : String,
        @owner_type : String,
        @created_at : Time,
        @pushed_at : Time,
        @stargazers_count : Int32,
        @topics : Array(String)
      )
      end
    end

    struct Options
      getter token : String
      getter max_repo_pages : Int32?

      def initialize(@token : String, @max_repo_pages : Int32?)
      end

      def self.from_argv(argv : Array(String)) : self
        token = ENV["GITHUB_TOKEN"]?.to_s
        if token.empty?
          raise Error.new("Set GITHUB_TOKEN environment variable.")
        end

        max_repo_pages = nil

        args = argv.dup
        if args.first? == "--"
          args.shift
        end

        i = 0
        while i < args.size
          case args[i]
          when "--max-repo-pages"
            max_repo_pages = args[i + 1]?.try(&.to_i)
            i += 2
          else
            raise Error.new("Unknown arg: #{args[i]}")
          end
        end

        new(token, max_repo_pages)
      end
    end

    struct Result
      getter window_start : Time
      getter repos_scanned : Int32
      getter unique_owners : Int32
      getter repos_pushed_last_30d : Int32
      getter repos_created_last_30d : Int32
      getter total_stars : Int64
      getter stars_bucket_0 : Int32
      getter stars_bucket_1_10 : Int32
      getter stars_bucket_11_100 : Int32
      getter stars_bucket_101_1000 : Int32
      getter stars_bucket_1001_plus : Int32
      getter repos_owner_user : Int32
      getter repos_owner_org : Int32
      getter top_topics_json : String

      def initialize(
        @window_start : Time,
        @repos_scanned : Int32,
        @unique_owners : Int32,
        @repos_pushed_last_30d : Int32,
        @repos_created_last_30d : Int32,
        @total_stars : Int64,
        @stars_bucket_0 : Int32,
        @stars_bucket_1_10 : Int32,
        @stars_bucket_11_100 : Int32,
        @stars_bucket_101_1000 : Int32,
        @stars_bucket_1001_plus : Int32,
        @repos_owner_user : Int32,
        @repos_owner_org : Int32,
        @top_topics_json : String
      )
      end
    end

    GITHUB_API        = "https://api.github.com"
    DEFAULT_PER_PAGE  = 100
    USER_AGENT        = "crystal-community-github-crystal-stats"
    MAX_SEARCH_PAGES  = 10
    MAX_RATE_LIMIT_WAITS = 32
    BASE_REPO_SEARCH       = "language:Crystal fork:false"
    STARS_TAIL_STEP        = 1_000_000_i64
    PUSHED_PARTITION_START = Time.utc(2008, 1, 1)
    TOP_TOPICS_LIMIT       = 40

    @request_log_io : IO? = nil
    @catalog_search_probe_count : Int32 = 0
    @catalog_search_page_fetches : Int32 = 0

    def initialize(@options : Options)
      @request_log_io = nil
    end

    def collect(io : IO = STDOUT, log_io : IO = STDERR) : Result
      @request_log_io = log_io
      begin
        collect_body(io, log_io)
      ensure
        @request_log_io = nil
      end
    end

    private def collect_body(io : IO, log_io : IO) : Result
      repos = fetch_crystal_repos(@options.token, @options.max_repo_pages, log_io)
      window_start = Time.utc - STATS_ROLLING_WINDOW

      owner_logins = Set(String).new
      repos_pushed_last_30d = 0
      repos_created_last_30d = 0
      total_stars = 0_i64
      stars_bucket_0 = 0
      stars_bucket_1_10 = 0
      stars_bucket_11_100 = 0
      stars_bucket_101_1000 = 0
      stars_bucket_1001_plus = 0
      repos_owner_user = 0
      repos_owner_org = 0
      topic_counts = Hash(String, Int32).new(default_value: 0)

      repos.each do |hit|
        unless bot_login?(hit.owner_login)
          owner_logins.add(hit.owner_login)
        end

        repos_pushed_last_30d += 1 if hit.pushed_at >= window_start
        repos_created_last_30d += 1 if hit.created_at >= window_start
        total_stars += hit.stargazers_count.to_i64

        case hit.stargazers_count
        when 0
          stars_bucket_0 += 1
        when 1..10
          stars_bucket_1_10 += 1
        when 11..100
          stars_bucket_11_100 += 1
        when 101..1000
          stars_bucket_101_1000 += 1
        else
          stars_bucket_1001_plus += 1
        end

        if hit.owner_type == "Organization"
          repos_owner_org += 1
        else
          repos_owner_user += 1
        end

        hit.topics.each do |t|
          topic_counts[t] += 1
        end
      end

      top_pairs = topic_counts.to_a.sort_by! { |(_, c)| -c }.first(TOP_TOPICS_LIMIT)
      top_topics_json = top_pairs.map { |topic, count| {"topic" => topic, "count" => count} }.to_json

      io.puts "30-day window start (UTC): #{window_start.to_s("%Y-%m-%d")}"
      io.puts "Crystal repos scanned (fork:false): #{repos.size}"
      io.puts "Unique owners with Crystal repo (bots excluded from this count): #{owner_logins.size}"
      io.puts "Repos pushed in last 30d: #{repos_pushed_last_30d}"
      io.puts "Repos created in last 30d: #{repos_created_last_30d}"
      io.puts "Total stars (sum of stargazers_count): #{total_stars}"
      io.puts "Star buckets 0 / 1–10 / 11–100 / 101–1000 / 1001+: #{stars_bucket_0} / #{stars_bucket_1_10} / #{stars_bucket_11_100} / #{stars_bucket_101_1000} / #{stars_bucket_1001_plus}"
      io.puts "Repos by owner type — User: #{repos_owner_user}, Organization: #{repos_owner_org}"
      io.puts "Top #{top_pairs.size} topics stored (#{topic_counts.size} distinct)."

      Result.new(
        window_start: window_start,
        repos_scanned: repos.size,
        unique_owners: owner_logins.size,
        repos_pushed_last_30d: repos_pushed_last_30d,
        repos_created_last_30d: repos_created_last_30d,
        total_stars: total_stars,
        stars_bucket_0: stars_bucket_0,
        stars_bucket_1_10: stars_bucket_1_10,
        stars_bucket_11_100: stars_bucket_11_100,
        stars_bucket_101_1000: stars_bucket_101_1000,
        stars_bucket_1001_plus: stars_bucket_1001_plus,
        repos_owner_user: repos_owner_user,
        repos_owner_org: repos_owner_org,
        top_topics_json: top_topics_json
      )
    end

    private def github_api_log : IO
      @request_log_io || STDERR
    end

    private def throttle_github_request
      ms = ENV["GITHUB_API_REQUEST_DELAY_MS"]?.try(&.to_i?) || 200
      return if ms <= 0
      sleep(ms.milliseconds)
    end

    private def rate_limit_response?(resp : HTTP::Client::Response) : Bool
      return true if resp.status_code == 429
      return false unless resp.status_code == 403
      b = resp.body
      b.includes?("rate limit") || b.includes?("API rate limit exceeded")
    end

    private def sleep_for_github_rate_limit(resp : HTTP::Client::Response, log_io : IO)
      if ra = resp.headers["Retry-After"]?.try(&.to_i?)
        secs = Math.max(ra, 1)
        log_io.puts "GitHub rate limit: Retry-After #{secs}s — sleeping..."
        sleep(secs.seconds)
        return
      end
      if reset_s = resp.headers["X-RateLimit-Reset"]?.try(&.to_i64?)
        wake = Time.unix(reset_s.to_i) + 2.seconds
        now = Time.utc
        span = wake - now
        span = 1.second if span < 1.second
        span = 3601.seconds if span > 3601.seconds
        rem = resp.headers["X-RateLimit-Remaining"]? || "?"
        log_io.puts "GitHub rate limit (remaining=#{rem}): sleeping #{span.total_seconds.to_i}s until quota reset..."
        sleep(span)
        return
      end
      log_io.puts "GitHub rate limit: sleeping 90s (no Retry-After / X-RateLimit-Reset)..."
      sleep(90.seconds)
    end

    private def bot_login?(login : String) : Bool
      login.ends_with?("[bot]")
    end

    private def github_get_json(path_with_query : String, token : String) : JSON::Any
      log_io = github_api_log
      rate_waits = 0
      loop do
        throttle_github_request
        url = URI.parse(GITHUB_API + path_with_query)
        headers = HTTP::Headers{
          "Accept"               => "application/vnd.github+json",
          "Authorization"        => "Bearer #{token}",
          "X-GitHub-Api-Version" => "2022-11-28",
          "User-Agent"           => USER_AGENT,
        }

        resp = HTTP::Client.get(url, headers)
        if rate_limit_response?(resp)
          rate_waits += 1
          if rate_waits > MAX_RATE_LIMIT_WAITS
            raise Error.new("GitHub rate limit: gave up after #{MAX_RATE_LIMIT_WAITS} waits. Increase GITHUB_API_REQUEST_DELAY_MS, or run again later.")
          end
          sleep_for_github_rate_limit(resp, log_io)
          next
        end
        unless (200..299).includes?(resp.status_code)
          raise Error.new("GET #{path_with_query} failed: HTTP #{resp.status_code}\n#{resp.body}")
        end
        return JSON.parse(resp.body)
      end
    end

    private def repo_hit_from_search_item(item : JSON::Any) : CrystalRepoHit
      topics = item["topics"]?.try(&.as_a).try(&.map(&.as_s)) || [] of String
      stars = item["stargazers_count"]?.try(&.as_i) || 0
      CrystalRepoHit.new(
        full_name: item["full_name"].as_s,
        owner_login: item["owner"]["login"].as_s,
        owner_type: item["owner"]["type"].as_s,
        created_at: Time.parse_iso8601(item["created_at"].as_s).to_utc,
        pushed_at: Time.parse_iso8601(item["pushed_at"].as_s).to_utc,
        stargazers_count: stars,
        topics: topics,
      )
    end

    private def fetch_crystal_repos(token : String, max_pages : Int32?, log_io : IO) : Array(CrystalRepoHit)
      fetch_crystal_repos_from_api(token, max_pages, log_io)
    end

    private def stars_partition_upper_bound : Int64
      ENV["GITHUB_CRYSTAL_STARS_PARTITION_MAX"]?.try(&.to_i64?) || 2_000_000_i64
    end

    private def search_repositories_total_count(q_raw : String, token : String) : Int32
      @catalog_search_probe_count += 1
      enc = URI.encode_www_form(q_raw)
      path = "/search/repositories?q=#{enc}&per_page=1&page=1"
      json = github_get_json(path, token)
      json["total_count"]?.try(&.as_i) || 0
    end

    private def fetch_search_query_pages_into(
      q_raw : String,
      token : String,
      log_io : IO,
      acc : Hash(String, CrystalRepoHit),
      label : String? = nil
    )
      enc = URI.encode_www_form(q_raw)
      page = 1
      loop do
        @catalog_search_page_fetches += 1
        path = "/search/repositories?q=#{enc}&per_page=#{DEFAULT_PER_PAGE}&page=#{page}"
        json = github_get_json(path, token)
        if json["incomplete_results"]?.try(&.as_bool) == true
          log_io.puts "  warning: incomplete_results for search slice"
        end
        items = json["items"].as_a
        break if items.empty?
        items.each do |item|
          hit = repo_hit_from_search_item(item)
          acc[hit.full_name] = hit
        end
        tag = label || q_raw
        log_io.puts "  #{tag} — page #{page}: +#{items.size} (catalog now #{acc.size} unique)"
        page += 1
        break if page > MAX_SEARCH_PAGES
      end
    end

    private def partition_star_range(lo : Int64, hi : Int64, token : String, log_io : IO, acc : Hash(String, CrystalRepoHit))
      q_raw = "#{BASE_REPO_SEARCH} stars:#{lo}..#{hi}"
      total = search_repositories_total_count(q_raw, token)
      return if total == 0
      if total <= 1000
        fetch_search_query_pages_into(q_raw, token, log_io, acc, "stars #{lo}..#{hi}")
        return
      end
      if lo < hi
        mid = (lo + hi) // 2
        partition_star_range(lo, mid, token, log_io, acc)
        partition_star_range(mid + 1, hi, token, log_io, acc)
      else
        log_io.puts "Repo catalog: stars=#{lo} has #{total} matches (>1000); subdividing by pushed date..."
        partition_pushed_window(PUSHED_PARTITION_START, Time.utc, "stars:#{lo}..#{hi}", token, log_io, acc)
      end
    end

    private def partition_pushed_window(lo_t : Time, hi_t : Time, stars_qual : String, token : String, log_io : IO, acc : Hash(String, CrystalRepoHit))
      lo_d = lo_t.to_utc.to_s("%Y-%m-%d")
      hi_d = hi_t.to_utc.to_s("%Y-%m-%d")
      q_raw = "#{BASE_REPO_SEARCH} #{stars_qual} pushed:#{lo_d}..#{hi_d}"
      total = search_repositories_total_count(q_raw, token)
      return if total == 0
      if total <= 1000
        fetch_search_query_pages_into(q_raw, token, log_io, acc, "pushed #{lo_d}..#{hi_d} #{stars_qual}")
        return
      end
      span = hi_t - lo_t
      if span >= 2.days
        mid_t = lo_t + span / 2
        partition_pushed_window(lo_t, mid_t, stars_qual, token, log_io, acc)
        partition_pushed_window(mid_t + 1.second, hi_t, stars_qual, token, log_io, acc)
      else
        log_io.puts "  WARNING: #{q_raw} still has total_count=#{total}>1000; keeping first 1000 (GitHub cap) — coverage gap."
        fetch_search_query_pages_into(q_raw, token, log_io, acc)
      end
    end

    private def consume_stars_strictly_above(bound : Int64, token : String, log_io : IO, acc : Hash(String, CrystalRepoHit))
      q_raw = "#{BASE_REPO_SEARCH} stars:>#{bound}"
      total = search_repositories_total_count(q_raw, token)
      return if total == 0
      if total <= 1000
        fetch_search_query_pages_into(q_raw, token, log_io, acc, "stars >#{bound}")
        return
      end
      lo = bound + 1
      hi = bound + STARS_TAIL_STEP
      log_io.puts "Repo catalog: stars>#{bound} has #{total} matches; narrowing #{lo}..#{hi}..."
      partition_star_range(lo, hi, token, log_io, acc)
      consume_stars_strictly_above(hi, token, log_io, acc)
    end

    private def fetch_crystal_repos_partitioned(token : String, log_io : IO) : Array(CrystalRepoHit)
      acc = Hash(String, CrystalRepoHit).new
      upper = stars_partition_upper_bound
      base_total = search_repositories_total_count(BASE_REPO_SEARCH, token)
      log_io.puts "Repo catalog: GitHub total_count≈#{base_total} for `#{BASE_REPO_SEARCH}` (max 1000 hits/query — partitioning when needed)"
      if base_total <= 1000
        fetch_search_query_pages_into(BASE_REPO_SEARCH, token, log_io, acc, "single-query catalog")
        arr = acc.values.sort_by!(&.full_name)
        log_io.puts "Repo catalog: #{arr.size} unique repos (single search, under cap)"
        return arr
      end
      partition_star_range(0_i64, upper, token, log_io, acc)
      consume_stars_strictly_above(upper, token, log_io, acc)
      arr = acc.values.sort_by!(&.full_name)
      log_io.puts "Repo catalog: #{arr.size} unique repos (partitioned search, target was ~#{base_total})"
      arr
    end

    private def fetch_crystal_repos_legacy_limited(token : String, max_pages : Int32, log_io : IO) : Array(CrystalRepoHit)
      by_name = Hash(String, CrystalRepoHit).new
      page = 1
      loop do
        break if page > max_pages
        @catalog_search_page_fetches += 1
        q = URI.encode_www_form(BASE_REPO_SEARCH)
        path = "/search/repositories?q=#{q}&per_page=#{DEFAULT_PER_PAGE}&page=#{page}"
        json = github_get_json(path, token)
        items = json["items"].as_a
        break if items.empty?
        items.each do |item|
          hit = repo_hit_from_search_item(item)
          by_name[hit.full_name] = hit
        end
        total_count = json["total_count"]?.try(&.as_i) || 0
        log_io.puts "Repos page #{page}: fetched #{items.size} (total_count=#{total_count})"
        page += 1
        break if page > MAX_SEARCH_PAGES
      end
      by_name.values.sort_by!(&.full_name)
    end

    private def fetch_crystal_repos_from_api(token : String, max_pages : Int32?, log_io : IO) : Array(CrystalRepoHit)
      @catalog_search_probe_count = 0
      @catalog_search_page_fetches = 0
      result = if mp = max_pages
        fetch_crystal_repos_legacy_limited(token, mp, log_io)
      else
        fetch_crystal_repos_partitioned(token, log_io)
      end
      total = @catalog_search_probe_count + @catalog_search_page_fetches
      log_io.puts "Repo catalog Search API summary: #{total} GET /search/repositories (#{@catalog_search_probe_count} total_count probes, #{@catalog_search_page_fetches} result pages)"
      result
    end
  end
end
