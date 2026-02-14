# Backfill latitude/longitude for users that have location but no coordinates.
# Respects Nominatim rate limit (1 req/s). Run with:
#   crystal run src/scripts/backfill_geocode.cr
require "../config/config"
require "../services/geocode_service"

users = CrystalCommunity::DB::User.needing_geocode
puts "Found #{users.size} users needing geocode."

users.each do |user|
  id = user.id.not_nil!
  loc = user.location.not_nil!.strip
  next if loc.empty?

  coords = CrystalCommunity::GeocodeService.lookup(loc)
  if coords
    CrystalCommunity::DB::User.update_coordinates(id, coords[0], coords[1])
    puts "Updated user #{id} (#{loc}) -> #{coords[0]}, #{coords[1]}"
  else
    puts "No coords for user #{id} (#{loc}), skipping"
  end

  sleep 1.seconds # Nominatim usage policy: max 1 request per second
end

puts "Done."
