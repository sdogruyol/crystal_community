require "faker"
require "../config/config"

module CrystalCommunity::Seeders
  class FakeUserGenerator
    DEFAULT_COUNT = 100

    # Generate a number of fake users and insert them into the database.
    # Uses the CrystalCommunity::DB::User model and the Faker shard.
    def run(count : Int32 = DEFAULT_COUNT)
      count.times do
        user = CrystalCommunity::DB::User.create(
          github_id: random_github_id,
          github_username: Faker::Internet.user_name,
          name: Faker::Name.name,
          bio: Faker::Lorem.sentence,
          location: Faker::Address.city,
          avatar_url: random_avatar_url,
          open_to_work: [true, false].sample,
          role: random_role,
          score: rand(0..10_000),
          projects_count: rand(0..50),
          posts_count: rand(0..100),
          comments_count: rand(0..300),
          stars_count: rand(0..500)
        )
      end
    end

    private def random_github_id : String
      # Generate a pseudo GitHub user ID as a string
      rand(1_i64..1_000_000_i64).to_s
    end

    private def random_avatar_url : String
      # Simple placeholder avatar URL based on a random ID
      id = rand(1..1_000_000)
      "https://avatars.githubusercontent.com/u/#{id}"
    end

    private def random_role : String
      # Small percentage of admins, rest developers
      rand(1..100) <= 5 ? "admin" : "developer"
    end
  end
end

CrystalCommunity::Seeders::FakeUserGenerator.new.run
