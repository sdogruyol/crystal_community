require "kemal"
require "../controllers/*"

get "/" { |env| CrystalCommunity::HomeController.index(env) }
