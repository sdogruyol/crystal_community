module CrystalCommunity::DB
  struct User
    include ::DB::Serializable
    property id : Int64?
    property github_id : String
    property github_username : String
    property name : String?
    property bio : String?
    property location : String?
    property latitude : Float64?
    property longitude : Float64?
    property avatar_url : String?
    property open_to_work : Bool
    property role : String
    property score : Int32
    property projects_count : Int32
    property posts_count : Int32
    property comments_count : Int32
    property stars_count : Int32
    property created_at : Time?
    property updated_at : Time?

    # Check if user is admin
    def admin? : Bool
      role == "admin"
    end

    # Check if user is developer
    def developer? : Bool
      role == "developer"
    end

    # Find user by ID
    def self.find(id : Int64) : User?
      SQL.query_one?("SELECT id, github_id, github_username, name, bio, location, latitude, longitude, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at FROM users WHERE id = $1", id, as: User)
    end

    # Find user by GitHub ID
    def self.find_by_github_id(github_id : String) : User?
      SQL.query_one?("SELECT id, github_id, github_username, name, bio, location, latitude, longitude, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at FROM users WHERE github_id = $1", github_id, as: User)
    end

    # Find user by GitHub username
    def self.find_by_github_username(username : String) : User?
      SQL.query_one?("SELECT id, github_id, github_username, name, bio, location, latitude, longitude, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at FROM users WHERE github_username = $1", username, as: User)
    end

    # Create a new user
    def self.create(**args) : User
      SQL.query_one(
        "INSERT INTO users (github_id, github_username, name, bio, location, latitude, longitude, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17) RETURNING *",
        args[:github_id], args[:github_username], args[:name], args[:bio], args[:location], args[:latitude]?, args[:longitude]?, args[:avatar_url], args[:open_to_work], args[:role], args[:score], args[:projects_count], args[:posts_count], args[:comments_count], args[:stars_count], Time.utc, Time.utc, as: User
      )
    end

    # Get all users
    def self.all : Array(User)
      SQL.query_all("SELECT id, github_id, github_username, name, bio, location, latitude, longitude, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at FROM users ORDER BY created_at DESC", as: User)
    end

    # Count total users
    def self.count : Int64
      SQL.scalar("SELECT COUNT(*) FROM users").as(Int64)
    end

    # Update user from GitHub data
    def self.update_from_github(id : Int64, name : String?, bio : String?, location : String?, avatar_url : String?) : User?
      SQL.exec(
        "UPDATE users SET name = $1, bio = $2, location = $3, avatar_url = $4, updated_at = $5 WHERE id = $6",
        name, bio, location, avatar_url, Time.utc, id
      )
      find(id)
    end

    # Update only latitude and longitude (e.g. after geocoding)
    def self.update_coordinates(id : Int64, latitude : Float64?, longitude : Float64?) : User?
      SQL.exec(
        "UPDATE users SET latitude = $1, longitude = $2, updated_at = $3 WHERE id = $4",
        latitude, longitude, Time.utc, id
      )
      find(id)
    end

    # Users that have location set but missing latitude/longitude (for backfill)
    def self.needing_geocode : Array(User)
      SQL.query_all(
        "SELECT id, github_id, github_username, name, bio, location, latitude, longitude, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at FROM users WHERE location IS NOT NULL AND trim(location) != '' AND (latitude IS NULL OR longitude IS NULL) ORDER BY id",
        as: User
      )
    end
  end
end
