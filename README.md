# Crystal Community

A community platform for Crystal developers to connect and discover each other. Built with the Crystal programming language and inspired by [rubycommunity.org](https://rubycommunity.org).

![Crystal Community](https://img.shields.io/badge/Crystal-1.19.1+-000000?style=flat-square&logo=crystal&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)
![Kemal](https://img.shields.io/badge/framework-Kemal-000000?style=flat-square)
![CI](https://github.com/sdogruyol/crystal_community/actions/workflows/ci.yml/badge.svg)

## ✨ Features

- 🔐 **GitHub OAuth Authentication** - Sign in with your GitHub account
- 🗺️ **Interactive Community Map** - Visualize developers around the world
- 👥 **Developer Directory** - Browse and discover Crystal developers
- 📝 **GitHub Profile Integration** - Automatically sync name, bio, location, and avatar from GitHub
- 🎨 **Modern UI** - Clean and responsive design

## 🚧 Planned Features

- 👤 **Developer Profiles** - Detailed profile pages for each developer
- 📊 **Activity Tracking** - Track projects, posts, comments, and stars
- 🏆 **Scoring System** - Gamified community engagement
- 💼 **Open to Work** - Mark your availability for opportunities

## 🛠️ Tech Stack

- **[Crystal](https://crystal-lang.org/)** - Fast, statically typed language
- **[Kemal](https://kemalcr.com/)** - Fast, effective web framework
- **[PostgreSQL](https://www.postgresql.org/)** - Robust relational database
- **[Micrate](https://github.com/amberframework/micrate)** - Database migrations
- **[Kemal Session](https://github.com/kemalcr/kemal-session)** - Session management

## 📋 Prerequisites

Before you begin, ensure you have the following installed:

- [Crystal](https://crystal-lang.org/install/) (>= 1.19.1)
- [PostgreSQL](https://www.postgresql.org/download/) (>= 12.0)
- [Git](https://git-scm.com/)

## 🚀 Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/your-username/crystal-community.git
   cd crystal-community
   ```

2. **Install dependencies**

   ```bash
   shards install
   ```

3. **Set up the database**

   ```bash
   # Create PostgreSQL database
   createdb crystal_community_development

   # Run migrations
   crystal run src/micrate.cr up
   ```

4. **Configure environment variables**

   Create a `.env.development` file in the project root:

   ```bash
   DATABASE_URL="postgres://localhost/crystal_community_development"
   GITHUB_CLIENT_ID="your_github_client_id"
   GITHUB_CLIENT_SECRET="your_github_client_secret"
   SESSION_SECRET="your-secret-key-change-this-in-production"
   CRYSTAL_COMMUNITY_ENV="development"
   ```

   **Getting GitHub OAuth Credentials:**
   - Go to [GitHub Settings > Developer settings > OAuth Apps](https://github.com/settings/developers)
   - Click "New OAuth App"
   - Set Application name: `Crystal Community (Development)`
   - Set Homepage URL: `http://localhost:3000`
   - Set Authorization callback URL: `http://localhost:3000/users/auth/github/callback`
   - Copy the Client ID and generate a Client Secret

5. **Build the application**

   ```bash
   crystal build src/app.cr -o crystal-community
   ```

## 🎮 Usage

### Running the Application

**Option 1: Direct execution**

```bash
crystal run src/app.cr
```

**Option 2: Using the compiled binary**

```bash
./crystal-community
```

The application will be available at `http://localhost:3000`

### Development with Auto-Reload

This project uses [sentry.cr](https://github.com/samueleaton/sentry) for automatic rebuild/restart during development.

**Installation:**

```bash
curl -fsSLo- https://raw.githubusercontent.com/samueleaton/sentry/master/install.cr | crystal eval
```

**Run with auto-reload:**

```bash
./sentry --install
./sentry
```

The `.sentry.yml` file is configured to build `src/app.cr` and run the `./crystal-community` binary, watching `src/**/*.cr` and `src/**/*.ecr` files.

### Development Data

Seed scripts for local development. Use `CRYSTAL_COMMUNITY_ENV=development` after database migrations and a configured `.env.development` (see **Installation** above).

#### Fake User Generator

Create fake users to test the map and developer directory:

```bash
CRYSTAL_COMMUNITY_ENV=development crystal run src/seeders/fake_user_generator.cr
```

Creates 100 fake users by default, with random names, bios, locations, avatar URLs, and other profile data.

#### Fake GitHub Stats Generator

Populate the `github_stats` table with synthetic rows so the stats page and charts have data without running the real GitHub collector:

```bash
CRYSTAL_COMMUNITY_ENV=development crystal run src/seeders/fake_github_stat_generator.cr
```

By default this inserts 30 rows with `collected_at` stepped back one day per row. `repos_scanned` and `total_stars` increase monotonically toward the present so time-series charts trend upward. Other fields (star buckets, owner split, top topics) are generated for plausible-looking dashboards.

## 📁 Project Structure

```
crystal-community/
├── db/
│   └── migrations/          # Database migrations
├── public/
│   └── assets/              # Static assets (CSS, JS, images)
├── spec/                    # Test files
├── src/
│   ├── app.cr               # Application entry point
│   ├── config/              # Configuration files
│   ├── controllers/         # Request handlers
│   ├── models/              # Data models
│   ├── routes/              # Route definitions
│   ├── seeders/             # Database seeders
│   └── views/               # ECR templates
├── .env.development         # Development environment variables
├── shard.yml                # Crystal dependencies
└── README.md
```

## 🧪 Testing

### Running Tests

Before running tests, make sure you have a test database set up:

```bash
# Create test database
createdb crystal_community_test

# Run migrations on test database
CRYSTAL_COMMUNITY_ENV=test crystal run src/micrate.cr -- up
```

Create a `.env.test` file in the project root with the following configuration:

```bash
DATABASE_URL="postgres://localhost/crystal_community_test"
GITHUB_CLIENT_ID="dummy_github_client_id"
GITHUB_CLIENT_SECRET="dummy_github_client_secret"
SESSION_SECRET="test-secret-key"
CRYSTAL_COMMUNITY_PORT=3001
GA_TRACKING_ID=""
```

Run the test suite:

```bash
KEMAL_ENV=test CRYSTAL_COMMUNITY_ENV=test crystal spec
```

The tests use [spec-kemal](https://github.com/kemalcr/spec-kemal) for E2E testing of Kemal routes and controllers.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Crystal's [style guide](https://crystal-lang.org/reference/conventions/coding_style.html)
- Write tests for new features
- Update documentation as needed
- Ensure migrations are reversible when possible

## 📝 Database Migrations

**Create a new migration:**

```bash
crystal run src/micrate.cr create migration_name
```

**Run migrations:**

```bash
crystal run src/micrate.cr up
```

**Rollback migrations:**

```bash
crystal run src/micrate.cr down
```

## 🔒 Security

- Always use strong `SESSION_SECRET` values in production
- Never commit `.env` files with real credentials
- Keep dependencies up to date
- Review OAuth scopes and permissions

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
