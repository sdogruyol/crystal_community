-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  github_id VARCHAR NOT NULL UNIQUE,
  github_username VARCHAR NOT NULL,
  name VARCHAR,
  bio TEXT,
  location VARCHAR,
  avatar_url VARCHAR,
  open_to_work BOOLEAN DEFAULT FALSE,
  role VARCHAR DEFAULT 'developer',
  score INTEGER DEFAULT 0,
  projects_count INTEGER DEFAULT 0,
  posts_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  stars_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_github_id ON users (github_id);
CREATE INDEX idx_users_github_username ON users (github_username);
CREATE INDEX idx_users_role ON users (role);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP INDEX idx_users_github_id;
DROP INDEX idx_users_github_username;
DROP INDEX idx_users_role;
DROP TABLE users;