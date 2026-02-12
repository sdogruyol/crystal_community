require "kemal"
require "../controllers/*"

get "/" { |env| HomeController.index(env) }
