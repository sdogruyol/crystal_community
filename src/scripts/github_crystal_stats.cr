# Hourly (or on-demand) GitHub stats for public Crystal repos. Persists one row per run to table `github_stats`.
#
# Without --since, the commit window defaults to 365 days ago at 00:00 UTC (same as GitHubCrystalStatsCollector::Options.from_argv).
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx crystal run src/scripts/github_crystal_stats.cr
#   GITHUB_TOKEN=ghp_xxx crystal run src/scripts/github_crystal_stats.cr -- --since 2025-04-26
#
# Or build once:
#   shards build github-crystal-stats
#   GITHUB_TOKEN=ghp_xxx ./bin/github-crystal-stats
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
