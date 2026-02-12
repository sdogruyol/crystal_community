require "micrate"
require "pg"
require "./config/config"

Micrate::DB.connection_url = CrystalCommunity::DB::URL
Micrate::Cli.run
