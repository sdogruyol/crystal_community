# Hourly (or on-demand) GitHub stats for public Crystal repos.
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx crystal run src/scripts/github_crystal_stats.cr -- --since 2025-04-26
#
# Or build once:
#   shards build github-crystal-stats
#   GITHUB_TOKEN=ghp_xxx ./bin/github-crystal-stats -- --since 2025-04-26

require "../config/constants"
require "../services/github_crystal_stats_collector"

begin
  options = CrystalCommunity::GitHubCrystalStatsCollector::Options.from_argv(ARGV)
  result = CrystalCommunity::GitHubCrystalStatsCollector.new(options).collect
  out_path = CrystalCommunity::GITHUB_CRYSTAL_STATS_JSON_PATH
  result.to_snapshot.save(out_path)
  STDERR.puts "Wrote snapshot to #{out_path}"
rescue ex : CrystalCommunity::GitHubCrystalStatsCollector::Error
  STDERR.puts "ERROR: #{ex.message}"
  exit 1
end
