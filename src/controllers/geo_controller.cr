class CrystalCommunity::GeoController
  # Geocode (cached server-side to reduce Nominatim calls)
  def self.geocode(env)
    q = env.params.query["q"]?.try(&.strip)
    if q.nil? || q.empty?
      env.response.status_code = 400
      env.response.print("Missing query parameter: q")
      env.response.close
    end

    coords = CrystalCommunity::GeocodeService.lookup(q.not_nil!)
    if coords
      env.response.content_type = "application/json"
      env.response.print({lat: coords[0], lon: coords[1]}.to_json)
    end
  end
end
