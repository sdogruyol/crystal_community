module CrystalCommunity::DB
  struct User
    include ::DB::Serializable
    property id : Int64?
    property github_id : String
    property github_username : String
    property name : String?
    property bio : String?
    property location : String?
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
      SQL.query_one?("SELECT id, github_id, github_username, name, bio, location, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at FROM users WHERE id = $1", id, as: User)
    end

    # Find user by GitHub ID
    def self.find_by_github_id(github_id : String) : User?
      SQL.query_one?("SELECT id, github_id, github_username, name, bio, location, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at FROM users WHERE github_id = $1", github_id, as: User)
    end

    # Find user by GitHub username
    def self.find_by_github_username(username : String) : User?
      SQL.query_one?("SELECT id, github_id, github_username, name, bio, location, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at FROM users WHERE github_username = $1", username, as: User)
    end

    # Create a new user
    def self.create(**args) : User
      user = User.new(**args)
      user.save
      user
    end

    # Save user to database
    def save : User
      if @id
        # Update existing user
        SQL.exec(
          "UPDATE users SET github_id = $1, github_username = $2, name = $3, bio = $4, location = $5, avatar_url = $6, open_to_work = $7, role = $8, score = $9, projects_count = $10, posts_count = $11, comments_count = $12, stars_count = $13, updated_at = $14 WHERE id = $15",
          @github_id, @github_username, @name, @bio, @location, @avatar_url, @open_to_work, @role, @score, @projects_count, @posts_count, @comments_count, @stars_count, Time.utc, @id
        )
      else
        # Insert new user
        @id = SQL.scalar(
          "INSERT INTO users (github_id, github_username, name, bio, location, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15) RETURNING id",
          @github_id, @github_username, @name, @bio, @location, @avatar_url, @open_to_work, @role, @score, @projects_count, @posts_count, @comments_count, @stars_count, Time.utc, Time.utc
        ).as(Int64)
      end
      self
    end

    # Get all users
    def self.all : Array(User)
      SQL.query_all("SELECT id, github_id, github_username, name, bio, location, avatar_url, open_to_work, role, score, projects_count, posts_count, comments_count, stars_count, created_at, updated_at FROM users ORDER BY created_at DESC", as: User)
    end

    # Count total users
    def self.count : Int64
      SQL.scalar("SELECT COUNT(*) FROM users").as(Int64)
    end
  end
end
