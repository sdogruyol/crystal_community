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
            Time.parse_utc("#{s}T00:00:00Z", "%Y-%m-%dT%H:%M:%SZ")
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

    def initialize(@options : Options)
    end

    def collect(io : IO = STDOUT, log_io : IO = STDERR) : Result
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

    private def bot_login?(login : String) : Bool
      login.ends_with?("[bot]")
    end

    private def github_get_json(path_with_query : String, token : String) : JSON::Any
      url = URI.parse(GITHUB_API + path_with_query)
      headers = HTTP::Headers{
        "Accept"               => "application/vnd.github+json",
        "Authorization"        => "Bearer #{token}",
        "X-GitHub-Api-Version" => "2022-11-28",
        "User-Agent"           => USER_AGENT,
      }

      resp = HTTP::Client.get(url, headers)
      if resp.status_code == 403 && resp.body.includes?("rate limit")
        raise Error.new("Rate limited by GitHub API. Try again later or reduce scope.")
      end
      unless (200..299).includes?(resp.status_code)
        raise Error.new("GET #{path_with_query} failed: HTTP #{resp.status_code}\n#{resp.body}")
      end
      JSON.parse(resp.body)
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
      repos = [] of Tuple(String, String)
      page = 1

      loop do
        break if max_pages && page > max_pages

        q = URI.encode_www_form("language:Crystal fork:false")
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
