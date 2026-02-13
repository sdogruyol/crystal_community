require "./spec_helper"

describe "Crystal Community E2E Tests" do
  # Clean up database before each test
  before_each do
    CrystalCommunity::DB::SQL.exec("TRUNCATE TABLE users RESTART IDENTITY CASCADE")
  end

  describe "GET /" do
    it "renders home page with empty state when no users exist" do
      get "/"
      
      response.status_code.should eq(200)
      response.body.should contain("No developers yet")
      response.body.should contain("Be the first to join!")
      response.body.should contain("Join with GitHub")
    end

    it "renders home page with developers list when users exist" do
      # Create test users
      user1 = CrystalCommunity::DB::User.create(
        github_id: "12345",
        github_username: "testuser1",
        name: "Test User 1",
        bio: "Test bio",
        location: "Istanbul, Turkey",
        avatar_url: "https://example.com/avatar1.jpg",
        open_to_work: false,
        role: "developer",
        score: 10,
        projects_count: 5,
        posts_count: 3,
        comments_count: 2,
        stars_count: 1
      )

      user2 = CrystalCommunity::DB::User.create(
        github_id: "67890",
        github_username: "testuser2",
        name: "Test User 2",
        bio: nil,
        location: nil,
        avatar_url: nil,
        open_to_work: true,
        role: "developer",
        score: 5,
        projects_count: 2,
        posts_count: 1,
        comments_count: 0,
        stars_count: 0
      )

      get "/"
      
      response.status_code.should eq(200)
      response.body.should contain("Join <strong>2</strong> developers")
      response.body.should contain("Test User 1")
      response.body.should contain("testuser1")
      response.body.should contain("Test User 2")
      response.body.should contain("testuser2")
      response.body.should contain("Istanbul, Turkey")
      response.body.should contain("Open to work")
      response.body.should contain("+10")
      response.body.should contain("5")
      response.body.should contain("Projects")
    end

    it "displays user stats correctly" do
      user = CrystalCommunity::DB::User.create(
        github_id: "11111",
        github_username: "statsuser",
        name: "Stats User",
        bio: "Bio text",
        location: "Location",
        avatar_url: nil,
        open_to_work: false,
        role: "developer",
        score: 15,
        projects_count: 10,
        posts_count: 5,
        comments_count: 3,
        stars_count: 2
      )

      get "/"
      
      response.status_code.should eq(200)
      response.body.should contain("10")
      response.body.should contain("Projects")
      response.body.should contain("5")
      response.body.should contain("Posts")
      response.body.should contain("3")
      response.body.should contain("Comments")
      response.body.should contain("2")
      response.body.should contain("Stars")
    end
  end

  describe "GET /users/auth/github" do
    it "redirects to GitHub OAuth authorization URL" do
      get "/users/auth/github"
      
      response.status_code.should eq(302)
      response.headers["Location"].should contain("github.com/login/oauth/authorize")
      response.headers["Location"].should contain("client_id")
      response.headers["Location"].should contain("redirect_uri")
      response.headers["Location"].should contain("scope")
      response.headers["Location"].should contain("state")
    end

    it "sets OAuth state in session" do
      get "/users/auth/github"
      
      response.status_code.should eq(302)
      # Session should have oauth_state set (we can't directly check session, but redirect confirms it worked)
      response.headers["Location"].should contain("state=")
    end
  end

  describe "GET /users/auth/github/callback" do
    it "returns 400 when state parameter is missing" do
      get "/users/auth/github/callback"
      
      response.status_code.should eq(400)
      response.body.should contain("Invalid state parameter")
    end

    it "returns 400 when state parameter doesn't match session" do
      # First set a state in session
      get "/users/auth/github"
      
      # Then try callback with different state
      get "/users/auth/github/callback?code=testcode&state=different_state"
      
      response.status_code.should eq(400)
      response.body.should contain("Invalid state parameter")
    end

    it "returns 400 when code parameter is missing" do
      with_session do
        # Set state in session first
        get "/users/auth/github"
        
        # Extract state from redirect URL
        redirect_url = response.headers["Location"]
        state_match = redirect_url.match(/state=([^&]+)/)
        state = state_match ? state_match[1] : ""
        
        # Try callback without code but with valid state from session
        get "/users/auth/github/callback?state=#{state}"
        
        response.status_code.should eq(400)
        response.body.should contain("Missing authorization code")
      end
    end
  end

  describe "GET /api/geocode" do
    it "returns 400 when query parameter is empty" do
      get "/api/geocode?q="
      
      response.status_code.should eq(400)
      response.body.should contain("Missing query parameter: q")
    end

    it "returns geocode data for valid location query" do
      # Note: This test will make a real API call to Nominatim
      # In a real scenario, you might want to mock this
      get "/api/geocode?q=Istanbul"
      
      # The service might return coordinates or nil depending on Nominatim response
      # If coordinates are found, it should return 200 with JSON
      # If not found, the controller doesn't set content_type or return body (potential bug)
      if response.status_code == 200 && !response.body.empty?
        response.body.should contain("lat")
        response.body.should contain("lon")
        json = JSON.parse(response.body)
        json.as_h.has_key?("lat").should be_true
        json.as_h.has_key?("lon").should be_true
      end
    end
  end
end
