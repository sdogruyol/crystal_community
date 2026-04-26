# Hourly (or on-demand) GitHub stats for public Crystal repos. Persists one row per run to table `github_stats`.
#
# Full repo catalog uses partitioned GitHub Search (stars, then pushed if a star bucket still has >1000 hits),
# because each search query returns at most 1000 items. Optional: GITHUB_CRYSTAL_STARS_PARTITION_MAX (default 2_000_000).
# Every run fetches the catalog from the API (no repo list cache).
#
# Committer counts: GET /repos/{owner}/{repo}/commits?since=… uses a rolling window of
# `GitHubCrystalStatsCollector::COMMITTER_FETCH_MAX_REPO_AGE` (1 year) from collection time (UTC).
# Only repos whose Search `created_at` falls in that same window are scanned for committers; older repos are skipped.
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx crystal run src/scripts/github_crystal_stats.cr
#   GITHUB_TOKEN=ghp_xxx crystal run src/scripts/github_crystal_stats.cr -- --max-repo-pages 2 --max-commit-pages 1
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
  span = CrystalCommunity::GitHubCrystalStatsCollector::COMMITTER_FETCH_MAX_REPO_AGE
  since = Time.utc - span
  STDERR.puts "Commit/repo window start #{since.to_utc.to_s("%Y-%m-%dT%H:%M:%SZ")} (#{span.inspect} rolling, UTC)"
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
