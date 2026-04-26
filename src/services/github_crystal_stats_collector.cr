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
  class GitHubCrystalStatsCollector
    class Error < Exception
    end

    struct Options
      getter token : String
      getter since : Time
      getter max_repo_pages : Int32?
      getter max_commit_pages_per_repo : Int32?

      def initialize(@token : String, @since : Time, @max_repo_pages : Int32?, @max_commit_pages_per_repo : Int32?)
      end

      def self.from_argv(argv : Array(String)) : self
        token = ENV["GITHUB_TOKEN"]?.to_s
        if token.empty?
          raise Error.new("Set GITHUB_TOKEN environment variable.")
        end

        since_str = nil
        max_repo_pages = nil
        max_commit_pages = nil

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

        new(token, since, max_repo_pages, max_commit_pages)
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
      repos = fetch_crystal_repos(@options.token, @options.max_repo_pages, log_io)

      owner_logins = Set(String).new
      repos.each do |(_full_name, owner_login)|
        next if bot_login?(owner_login)
        owner_logins.add(owner_login)
      end

      unique_committers = Set(String).new

      repos.each_with_index do |(full_name, _owner), idx|
        log_io.puts "[#{idx + 1}/#{repos.size}] Fetching committers for #{full_name} since #{@options.since}..."
        committers = fetch_committers_for_repo(
          @options.token,
          full_name,
          @options.since,
          @options.max_commit_pages_per_repo
        )
        committers.each { |l| unique_committers.add(l) }
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

    # Search public repos: language:Crystal fork:false
    private def fetch_crystal_repos(token : String, max_pages : Int32?, log_io : IO) : Array(Tuple(String, String))
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
