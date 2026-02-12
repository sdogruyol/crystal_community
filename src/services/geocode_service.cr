require "http/client"
require "json"

# In-memory cache for Nominatim geocode results. Reduces external API calls.
module CrystalCommunity::GeocodeService
  CACHE = {} of String => Array(Float64)

  def self.lookup(location : String) : Array(Float64)?
    key = location.strip
    return nil if key.empty?
    return CACHE[key].dup if CACHE[key]?

    url = "https://nominatim.openstreetmap.org/search?format=json&q=#{URI.encode_www_form(key)}"
    response = HTTP::Client.get(url, headers: HTTP::Headers{"Accept-Language" => "en"})
    data = JSON.parse(response.body)

    return nil unless data.as_a.size > 0

    first = data.as_a[0]
    lat = first["lat"].as_s.to_f
    lon = first["lon"].as_s.to_f
    coords = [lat, lon]
    CACHE[key] = coords
    coords
  rescue
    nil
  end
end
