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
  # - Excludes bots by login suffix `"[bot]"`.
  # - For commits: counts only those with `committer.login` present.
  # - Repo catalog and per-repo committer sets can be file-cached (TTL); see collect() and Options.
  class GitHubCrystalStatsCollector
    class Error < Exception
    end

    struct Options
      getter token : String
      getter since : Time
      getter max_repo_pages : Int32?
      getter max_commit_pages_per_repo : Int32?
      getter refresh_repo_catalog : Bool
      getter refresh_commits_cache : Bool

      def initialize(
        @token : String,
        @since : Time,
        @max_repo_pages : Int32?,
        @max_commit_pages_per_repo : Int32?,
        @refresh_repo_catalog : Bool = false,
        @refresh_commits_cache : Bool = false
      )
      end

      def self.from_argv(argv : Array(String)) : self
        token = ENV["GITHUB_TOKEN"]?.to_s
        if token.empty?
          raise Error.new("Set GITHUB_TOKEN environment variable.")
        end

        since_str = nil
        max_repo_pages = nil
        max_commit_pages = nil
        refresh_repo_catalog = false
        refresh_commits_cache = false

        args = argv.dup
        if args.first? == "--"
          args.shift
        end

        i = 0
        while i < args.size
          case args[i]
          when "--since"
            since_str = args[i + 1]?
            i += 2
          when "--max-repo-pages"
            max_repo_pages = args[i + 1]?.try(&.to_i)
            i += 2
          when "--max-commit-pages"
            max_commit_pages = args[i + 1]?.try(&.to_i)
            i += 2
          when "--refresh-repos"
            refresh_repo_catalog = true
            i += 1
          when "--refresh-commits"
            refresh_commits_cache = true
            i += 1
          else
            raise Error.new("Unknown arg: #{args[i]}")
          end
        end

        since =
          if s = since_str
            if s.matches?(/^\d{4}-\d{2}-\d{2}$/)
              Time.parse_utc("#{s}T00:00:00Z", "%Y-%m-%dT%H:%M:%SZ")
            elsif s.matches?(/^\d+$/)
              days = s.to_i
              raise Error.new("--since: day count must be >= 1 (got #{days})") if days < 1
              Time.utc - days.days
            else
              raise Error.new("Invalid --since #{s.inspect}: use YYYY-MM-DD or a day count (e.g. 3650)")
            end
          else
            Time.utc - 365.days
          end

        new(token, since, max_repo_pages, max_commit_pages, refresh_repo_catalog, refresh_commits_cache)
      end
    end

    struct Result
      getter since : Time
      getter repos_scanned : Int32
      getter unique_owners : Int32
      getter unique_committers : Int32

      def initialize(@since : Time, @repos_scanned : Int32, @unique_owners : Int32, @unique_committers : Int32)
      end
    end

    GITHUB_API        = "https://api.github.com"
    DEFAULT_PER_PAGE  = 100
    USER_AGENT        = "crystal-community-github-crystal-stats"
    MAX_SEARCH_PAGES  = 10
    MAX_RATE_LIMIT_WAITS = 32
    # GitHub Search returns at most 1000 results per query; we subdivide by stars (then pushed) to widen coverage.
    BASE_REPO_SEARCH       = "language:Crystal fork:false"
    STARS_TAIL_STEP        = 1_000_000_i64
    PUSHED_PARTITION_START = Time.utc(2008, 1, 1)

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
      repos = fetch_crystal_repos(@options.token, @options.max_repo_pages, @options.refresh_repo_catalog, log_io)

      owner_logins = Set(String).new
      repos.each do |(_full_name, owner_login)|
        next if bot_login?(owner_login)
        owner_logins.add(owner_login)
      end

      unique_committers = Set(String).new
      use_commits_cache = commits_cache_enabled?
      since_key = commits_since_cache_key
      commits_cache : Hash(String, CommitsRepoCacheEntry)? = nil
      if use_commits_cache
        commits_cache = if @options.refresh_commits_cache
          log_io.puts "Committers cache: --refresh-commits, rebuilding all repo entries from API"
          Hash(String, CommitsRepoCacheEntry).new
        else
          load_commits_cache_window(since_key, log_io)
        end
      end
      commits_cache_dirty = false

      repos.each_with_index do |(full_name, _owner), idx|
        committers = if use_commits_cache
          cc = commits_cache.not_nil!
          if !@options.refresh_commits_cache && (ent = cc[full_name]?)
            age = Time.utc - ent[:fetched_at]
            if age <= commits_cache_ttl
              log_io.puts "[#{idx + 1}/#{repos.size}] #{full_name} (committers cache hit, age #{age.inspect})"
              ent[:logins]
            else
              log_io.puts "[#{idx + 1}/#{repos.size}] Fetching committers for #{full_name} since #{@options.since}..."
              fresh = fetch_committers_for_repo(
                @options.token,
                full_name,
                @options.since,
                @options.max_commit_pages_per_repo
              )
              cc[full_name] = {fetched_at: Time.utc, logins: fresh}
              commits_cache_dirty = true
              fresh
            end
          else
            log_io.puts "[#{idx + 1}/#{repos.size}] Fetching committers for #{full_name} since #{@options.since}..."
            fresh = fetch_committers_for_repo(
              @options.token,
              full_name,
              @options.since,
              @options.max_commit_pages_per_repo
            )
            cc[full_name] = {fetched_at: Time.utc, logins: fresh}
            commits_cache_dirty = true
            fresh
          end
        else
          log_io.puts "[#{idx + 1}/#{repos.size}] Fetching committers for #{full_name} since #{@options.since}..."
          fetch_committers_for_repo(
            @options.token,
            full_name,
            @options.since,
            @options.max_commit_pages_per_repo
          )
        end

        committers.each { |l| unique_committers.add(l) }
      end

      if use_commits_cache && commits_cache_dirty
        write_commits_cache_window(since_key, commits_cache.not_nil!, log_io)
      end

      io.puts "Since (committer-date via since filter): #{@options.since.to_s("%Y-%m-%d")}"
      io.puts "Crystal repos scanned (fork:false): #{repos.size}"
      io.puts "Unique owners with Crystal repo (org+user, bots excluded): #{owner_logins.size}"
      io.puts "Unique committers in Crystal repos since #{@options.since.to_s("%Y-%m-%d")} (committer.login only, bots excluded): #{unique_committers.size}"

      Result.new(
        since: @options.since,
        repos_scanned: repos.size,
        unique_owners: owner_logins.size,
        unique_committers: unique_committers.size
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
            raise Error.new("GitHub rate limit: gave up after #{MAX_RATE_LIMIT_WAITS} waits. Increase GITHUB_API_REQUEST_DELAY_MS, shorten --since, or run again later (commit cache will resume).")
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

    # Search public repos: language:Crystal fork:false.
    # Uses a JSON file cache (TTL) so hourly cron does not re-hit the Search API every run.
    # Cache is skipped when +max_pages+ is set, or when +force_refresh+ is true, or via --refresh-repos.
    private def fetch_crystal_repos(token : String, max_pages : Int32?, force_refresh : Bool, log_io : IO) : Array(Tuple(String, String))
      use_cache = max_pages.nil? && !force_refresh

      if use_cache
        if cached = read_repo_catalog_cache?(log_io)
          log_io.puts "Repo catalog: using cache (#{cached.size} repos, TTL #{repo_cache_ttl.inspect})"
          return cached
        end
      else
        log_io.puts "Repo catalog: fetching live (cache disabled: max_pages=#{max_pages.inspect}, refresh=#{force_refresh})"
      end

      repos = fetch_crystal_repos_from_api(token, max_pages, log_io)

      if use_cache
        write_repo_catalog_cache(repos, log_io)
      end

      repos
    end

    private def repo_cache_path : String
      ENV["GITHUB_CRYSTAL_REPOS_CACHE_PATH"]? || File.join("data", "github_crystal_repos_cache.json")
    end

    private def repo_cache_ttl : Time::Span
      ttl_hours_from_env("GITHUB_CRYSTAL_REPOS_CACHE_TTL_HOURS")
    end

    private def commits_cache_path : String
      ENV["GITHUB_CRYSTAL_COMMITS_CACHE_PATH"]? || File.join("data", "github_crystal_commits_cache.json")
    end

    private def commits_cache_ttl : Time::Span
      ttl_hours_from_env("GITHUB_CRYSTAL_COMMITS_CACHE_TTL_HOURS")
    end

    private def ttl_hours_from_env(name : String) : Time::Span
      hours = ENV[name]?.try(&.to_i?) || 24
      hours = 24 if hours < 1
      hours.hours
    end

    private def commits_since_cache_key : String
      @options.since.to_utc.to_s("%Y-%m-%dT%H:%M:%SZ")
    end

    private def commits_cache_enabled? : Bool
      @options.max_commit_pages_per_repo.nil?
    end

    private alias CommitsRepoCacheEntry = NamedTuple(fetched_at: Time, logins: Set(String))

    private def load_commits_cache_window(since_key : String, log_io : IO) : Hash(String, CommitsRepoCacheEntry)
      path = commits_cache_path
      unless File.file?(path)
        return Hash(String, CommitsRepoCacheEntry).new
      end

      raw = File.read(path)
      json = JSON.parse(raw)
      windows = json["windows"]?.try(&.as_h?) || Hash(String, JSON::Any).new
      win = windows[since_key]?.try(&.as_h?)
      unless win
        return Hash(String, CommitsRepoCacheEntry).new
      end

      repos_json = win["repos"]?.try(&.as_h?) || Hash(String, JSON::Any).new
      result = Hash(String, CommitsRepoCacheEntry).new
      repos_json.each do |full_name, entry|
        h = entry.as_h
        t = Time.parse_iso8601(h["fetched_at"].as_s).to_utc
        logins = Set.new(h["logins"].as_a.map(&.as_s))
        result[full_name] = {fetched_at: t, logins: logins}
      end
      result
    rescue ex : JSON::ParseException | ArgumentError | KeyError
      log_io.puts "Commits cache unreadable (#{ex.message}), starting empty for window #{since_key}"
      Hash(String, CommitsRepoCacheEntry).new
    end

    private def write_commits_cache_window(since_key : String, data : Hash(String, CommitsRepoCacheEntry), log_io : IO)
      path = commits_cache_path
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)

      final_windows = Hash(String, JSON::Any).new
      if File.file?(path)
        begin
          old_root = JSON.parse(File.read(path))
          old_root["windows"]?.try(&.as_h).try &.each do |k, v|
            final_windows[k] = v unless k == since_key
          end
        rescue JSON::ParseException
          # overwrite with fresh structure
        end
      end
      final_windows[since_key] = commits_window_to_json_any(data)

      payload = {"version" => JSON::Any.new(1_i64), "windows" => JSON::Any.new(final_windows)}
      File.write(path, payload.to_json)
      log_io.puts "Committers cache: wrote #{data.size} repos for since #{since_key} to #{path}"
    end

    private def commits_window_to_json_any(data : Hash(String, CommitsRepoCacheEntry)) : JSON::Any
      repos_inner = Hash(String, Hash(String, Array(String) | String)).new
      data.each do |fn, e|
        repos_inner[fn] = {
          "fetched_at" => e[:fetched_at].to_utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
          "logins"     => e[:logins].to_a,
        }
      end
      JSON.parse({"repos" => repos_inner}.to_json)
    end

    private def read_repo_catalog_cache?(log_io : IO) : Array(Tuple(String, String))?
      path = repo_cache_path
      return nil unless File.file?(path)
      raw = File.read(path)
      json = JSON.parse(raw)
      fetched_at = Time.parse_iso8601(json["fetched_at"].as_s).to_utc
      age = Time.utc - fetched_at
      if age > repo_cache_ttl
        log_io.puts "Repo catalog cache stale (#{age.inspect} old at #{path}), refreshing from API"
        return nil
      end
      items = json["repos"].as_a
      repos = items.map do |row|
        pair = row.as_a
        {pair[0].as_s, pair[1].as_s}
      end
      repos
    rescue ex : JSON::ParseException | ArgumentError | IndexError
      log_io.puts "Repo catalog cache unreadable (#{ex.message}), refreshing from API"
      nil
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
      acc : Set(Tuple(String, String)),
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
          full_name = item["full_name"].as_s
          owner_login = item["owner"]["login"].as_s
          acc << {full_name, owner_login}
        end
        tag = label || q_raw
        log_io.puts "  #{tag} — page #{page}: +#{items.size} (catalog now #{acc.size} unique)"
        page += 1
        break if page > MAX_SEARCH_PAGES
      end
    end

    private def partition_star_range(lo : Int64, hi : Int64, token : String, log_io : IO, acc : Set(Tuple(String, String)))
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

    private def partition_pushed_window(lo_t : Time, hi_t : Time, stars_qual : String, token : String, log_io : IO, acc : Set(Tuple(String, String)))
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

    private def consume_stars_strictly_above(bound : Int64, token : String, log_io : IO, acc : Set(Tuple(String, String)))
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

    private def fetch_crystal_repos_partitioned(token : String, log_io : IO) : Array(Tuple(String, String))
      acc = Set(Tuple(String, String)).new
      upper = stars_partition_upper_bound
      base_total = search_repositories_total_count(BASE_REPO_SEARCH, token)
      log_io.puts "Repo catalog: GitHub total_count≈#{base_total} for `#{BASE_REPO_SEARCH}` (max 1000 hits/query — partitioning when needed)"
      if base_total <= 1000
        fetch_search_query_pages_into(BASE_REPO_SEARCH, token, log_io, acc, "single-query catalog")
        arr = acc.to_a
        log_io.puts "Repo catalog: #{arr.size} unique repos (single search, under cap)"
        return arr
      end
      partition_star_range(0_i64, upper, token, log_io, acc)
      consume_stars_strictly_above(upper, token, log_io, acc)
      arr = acc.to_a
      log_io.puts "Repo catalog: #{arr.size} unique repos (partitioned search, target was ~#{base_total})"
      arr
    end

    private def fetch_crystal_repos_legacy_limited(token : String, max_pages : Int32, log_io : IO) : Array(Tuple(String, String))
      repos = [] of Tuple(String, String)
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
          full_name = item["full_name"].as_s
          owner_login = item["owner"]["login"].as_s
          repos << {full_name, owner_login}
        end
        total_count = json["total_count"]?.try(&.as_i) || 0
        log_io.puts "Repos page #{page}: fetched #{items.size} (total_count=#{total_count})"
        page += 1
        break if page > MAX_SEARCH_PAGES
      end
      repos
    end

    private def write_repo_catalog_cache(repos : Array(Tuple(String, String)), log_io : IO)
      path = repo_cache_path
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      payload = {
        "fetched_at" => Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
        "repos"      => repos.map { |(fn, o)| [fn, o] of String },
      }
      File.write(path, payload.to_json)
      log_io.puts "Repo catalog: wrote cache (#{repos.size} repos) to #{path}"
    end

    private def fetch_crystal_repos_from_api(token : String, max_pages : Int32?, log_io : IO) : Array(Tuple(String, String))
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

    private def fetch_committers_for_repo(token : String, full_name : String, since : Time, max_pages : Int32?) : Set(String)
      owner, repo = full_name.split("/", 2)
      committers = Set(String).new
      page = 1
      since_iso = since.to_s("%Y-%m-%dT%H:%M:%SZ")

      loop do
        break if max_pages && page > max_pages

        path = "/repos/#{owner}/#{repo}/commits?since=#{URI.encode_www_form(since_iso)}&per_page=#{DEFAULT_PER_PAGE}&page=#{page}"
        json = github_get_json(path, token)
        arr = json.as_a
        break if arr.empty?

        arr.each do |c|
          committer = c["committer"]?
          next unless committer && committer.raw != nil
          login = committer["login"]?.try(&.as_s)
          next unless login
          next if bot_login?(login)
          committers.add(login)
        end

        page += 1
      end

      committers
    end
  end
end
