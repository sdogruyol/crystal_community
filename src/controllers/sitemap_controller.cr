require "kemal"
require "time"

class CrystalCommunity::SitemapController
  def self.index(env)
    host = env.request.headers["Host"]? || "localhost:3000"
    scheme = env.request.headers["X-Forwarded-Proto"]? || "http"
    base_url = "#{scheme}://#{host}"

    # Get current date in ISO 8601 format
    lastmod = Time.local.to_s("%Y-%m-%d")

    # Build sitemap XML
    sitemap = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>#{base_url}/</loc>
    <lastmod>#{lastmod}</lastmod>
    <changefreq>daily</changefreq>
    <priority>1.0</priority>
  </url>
</urlset>
XML

    env.response.content_type = "application/xml"
    env.response.headers["Cache-Control"] = "public, max-age=3600"
    sitemap
  end
end
