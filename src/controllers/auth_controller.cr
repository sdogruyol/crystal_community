require "kemal"
require "http/client"
require "json"
require "random/secure"

class CrystalCommunity::AuthController
  GITHUB_AUTHORIZE_URL = "https://github.com/login/oauth/authorize"
  GITHUB_TOKEN_URL     = "https://github.com/login/oauth/access_token"
  GITHUB_USER_URL      = "https://api.github.com/user"

  # Redirect to GitHub OAuth
  def self.github(env)
    client_id = ENV["GITHUB_CLIENT_ID"]? || raise "GITHUB_CLIENT_ID not set"

    # Build redirect URI
    host = CrystalCommunity::ENVIRONMENT == "production" ? "crystalcommunity.org" : "localhost:3000"
    scheme = CrystalCommunity::ENVIRONMENT == "production" ? "https" : "http"
    redirect_uri = "#{scheme}://#{host}/users/auth/github/callback"

    # Generate state for CSRF protection
    state = Random::Secure.hex(32)
    env.session.string("oauth_state", state)

    # Build GitHub OAuth URL
    params = URI::Params.encode({
      "client_id"    => client_id,
      "redirect_uri" => redirect_uri,
      "scope"        => "read:user user:email",
      "state"        => state,
    })

    github_url = "#{GITHUB_AUTHORIZE_URL}?#{params}"
    env.redirect github_url
  end

  # Handle GitHub OAuth callback
  def self.github_callback(env)
    code = env.params.query["code"]?
    state = env.params.query["state"]?
    stored_state = env.session.string?("oauth_state")

    # Verify state to prevent CSRF attacks
    if state.nil? || stored_state.nil? || state != stored_state
      env.response.status_code = 400
      return "Invalid state parameter"
    end

    # Clear state from session
    env.session.delete_string("oauth_state")

    if code.nil?
      env.response.status_code = 400
      return "Missing authorization code"
    end

    # Exchange code for access token
    access_token = exchange_code_for_token(code, env)
    if access_token.nil?
      env.response.status_code = 500
      return "Failed to obtain access token"
    end

    # Get user info from GitHub
    user_data = get_github_user(access_token)
    if user_data.nil?
      env.response.status_code = 500
      return "Failed to fetch user data"
    end

    # Safely extract user data from GitHub API response
    # Handle null values gracefully
    begin
      # Required fields - these should always be present
      github_id = user_data["id"]?.try(&.as_i) || user_data["id"].as_i
      github_id = github_id.to_s

      github_username = user_data["login"]?.try(&.as_s) || user_data["login"].as_s

      # Optional fields - these can be null in GitHub API
      # Use safe extraction that handles null values
      name = extract_github_data_safely(user_data, "name")
      bio = extract_github_data_safely(user_data, "bio")
      location = extract_github_data_safely(user_data, "location")
      avatar_url = extract_github_data_safely(user_data, "avatar_url")
    rescue ex
      env.response.status_code = 500
      return "Failed to parse Github data: #{ex.message}"
    end

    user = CrystalCommunity::DB::User.find_by_github_id(github_id)

    if user.nil?
      # Geocode location once at signup and store coordinates
      lat = nil
      lon = nil
      if location && !location.strip.empty?
        coords = CrystalCommunity::GeocodeService.lookup(location)
        lat = coords[0]? if coords
        lon = coords[1]? if coords
      end

      # Create new user
      user = CrystalCommunity::DB::User.create(
        github_id: github_id,
        github_username: github_username,
        name: name,
        bio: bio,
        location: location,
        latitude: lat,
        longitude: lon,
        avatar_url: avatar_url,
        open_to_work: false,
        role: "developer",
        score: 0,
        projects_count: 0,
        posts_count: 0,
        comments_count: 0,
        stars_count: 0
      )
    else
      # Update existing user with latest GitHub data
      updated_user = CrystalCommunity::DB::User.update_from_github(
        user.id.not_nil!,
        name,
        bio,
        location,
        avatar_url
      )
      user = updated_user if updated_user

      # Update coordinates: geocode if location present, else clear
      user_id = user.not_nil!.id.not_nil!
      if location && !location.strip.empty?
        coords = CrystalCommunity::GeocodeService.lookup(location)
        if coords
          CrystalCommunity::DB::User.update_coordinates(user_id, coords[0], coords[1])
        end
      else
        CrystalCommunity::DB::User.update_coordinates(user_id, nil, nil)
      end
      user = CrystalCommunity::DB::User.find(user_id) || user
    end

    # Set user session
    env.session.int("user_id", user.id.not_nil!.to_i)

    # Redirect to home page
    env.redirect "/"
  end

  private def self.exchange_code_for_token(code : String, env) : String?
    client_id = ENV["GITHUB_CLIENT_ID"]? || raise "GITHUB_CLIENT_ID not set"
    client_secret = ENV["GITHUB_CLIENT_SECRET"]? || raise "GITHUB_CLIENT_SECRET not set"

    # Build redirect URI (must match the one used in github method)
    host = CrystalCommunity::ENVIRONMENT == "production" ? "crystalcommunity.org" : "localhost:3000"
    scheme = CrystalCommunity::ENVIRONMENT == "production" ? "https" : "http"
    redirect_uri = "#{scheme}://#{host}/users/auth/github/callback"

    body = URI::Params.encode({
      "client_id"     => client_id,
      "client_secret" => client_secret,
      "code"          => code,
      "redirect_uri"  => redirect_uri,
    })

    headers = HTTP::Headers{
      "Accept"       => "application/json",
      "Content-Type" => "application/x-www-form-urlencoded",
    }

    response = HTTP::Client.post(
      GITHUB_TOKEN_URL,
      headers: headers,
      body: body
    )

    if response.status_code == 200
      json = JSON.parse(response.body)
      json["access_token"]?.try(&.as_s)
    end
  rescue
    nil
  end

  private def self.get_github_user(access_token : String) : JSON::Any?
    headers = HTTP::Headers{
      "Authorization" => "Bearer #{access_token}",
      "Accept"        => "application/vnd.github.v3+json",
      "User-Agent"    => "CrystalCommunity",
    }

    response = HTTP::Client.get(
      GITHUB_USER_URL,
      headers: headers
    )

    if response.status_code == 200
      JSON.parse(response.body)
    end
  rescue
    nil
  end

  # Safely extract string value from JSON::Any, handling null values
  private def self.extract_github_data_safely(data : JSON::Any, key : String) : String?
    value = data[key]?
    return nil if value.nil?

    # Check if the value is null in JSON by checking raw value
    return nil if value.raw.nil?

    # Try to extract as string
    value.as_s
  rescue
    nil
  end
end
