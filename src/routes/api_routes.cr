# Geocode route
get "/api/geocode" { |env| CrystalCommunity::GeoController.geocode(env) }
