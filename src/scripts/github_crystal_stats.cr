# Hourly (or on-demand) GitHub stats for public Crystal repos. Persists one row per run to table `github_stats`.
#
# Without --since, the commit window defaults to 365 days ago at 00:00 UTC (same as GitHubCrystalStatsCollector::Options.from_argv).
#
# Full repo catalog uses partitioned GitHub Search (stars, then pushed if a star bucket still has >1000 hits),
# because each search query returns at most 1000 items. Optional: GITHUB_CRYSTAL_STARS_PARTITION_MAX (default 2_000_000).
#
# Repo list (`language:Crystal fork:false`) is cached under data/github_crystal_repos_cache.json for
# GITHUB_CRYSTAL_REPOS_CACHE_TTL_HOURS (default 24) to avoid GitHub Search API pagination on every run.
# Override path with GITHUB_CRYSTAL_REPOS_CACHE_PATH. Force a fresh catalog with --refresh-repos.
# (--max-repo-pages disables cache read/write so tests do not poison the file.)
#
# Per-repo committer sets (/repos/.../commits) are cached in data/github_crystal_commits_cache.json, keyed by
# the exact commit --since instant, with GITHUB_CRYSTAL_COMMITS_CACHE_TTL_HOURS (default 24).
# GITHUB_CRYSTAL_COMMITS_CACHE_PATH overrides the file path. Use --refresh-commits to refetch every repo this run.
# (--max-commit-pages disables this cache, same as repo list.)
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx crystal run src/scripts/github_crystal_stats.cr
#   GITHUB_TOKEN=ghp_xxx crystal run src/scripts/github_crystal_stats.cr -- --refresh-repos
#   GITHUB_TOKEN=ghp_xxx crystal run src/scripts/github_crystal_stats.cr -- --refresh-commits
#   GITHUB_TOKEN=ghp_xxx crystal run src/scripts/github_crystal_stats.cr -- --since 2025-04-26
#
# Or build once:
#   shards build github-crystal-stats
#   GITHUB_TOKEN=ghp_xxx ./bin/github-crystal-stats
#
# GitHub REST: on 403/429 rate limit the collector sleeps until X-RateLimit-Reset (or Retry-After) and retries.
# Space requests with GITHUB_API_REQUEST_DELAY_MS (default 200) to reduce secondary throttling on big runs.
#
# Requires DATABASE_URL (and .env.* loaded from project root when present).

require "dotenv"

case ENV["CRYSTAL_COMMUNITY_ENV"]? || "development"
when "production"
  Dotenv.load ".env.production"
when "staging"
  Dotenv.load ".env.staging"
when "test"
  Dotenv.load ".env.test" unless ENV["CI"]?
else
  Dotenv.load ".env.development"
end

require "../config/database"
require "../models/github_stat"
require "../services/github_crystal_stats_collector"

begin
  options = CrystalCommunity::GitHubCrystalStatsCollector::Options.from_argv(ARGV)
  STDERR.puts "Commit window since #{options.since.to_utc.to_s("%Y-%m-%dT%H:%M:%SZ")} (omit --since for 365-day default)"
  result = CrystalCommunity::GitHubCrystalStatsCollector.new(options).collect
  row = CrystalCommunity::DB::GithubStat.insert!(
    since: result.since,
    repos_scanned: result.repos_scanned,
    unique_owners: result.unique_owners,
    unique_committers: result.unique_committers,
    collected_at: Time.utc
  )
  STDERR.puts "Saved github_stats id=#{row.id} collected_at=#{row.collected_at}"
rescue ex : CrystalCommunity::GitHubCrystalStatsCollector::Error
  STDERR.puts "ERROR: #{ex.message}"
  exit 1
end
