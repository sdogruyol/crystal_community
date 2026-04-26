module CrystalCommunity
  ENVIRONMENT = ENV["CRYSTAL_COMMUNITY_ENV"]? || "development"
  GA_TRACKING_ID = ENV["CRYSTAL_COMMUNITY_GA_TRACKING_ID"]?
  GITHUB_CRYSTAL_STATS_JSON_PATH = ENV["GITHUB_CRYSTAL_STATS_JSON"]? || File.join("data", "github_crystal_stats.json")
end
