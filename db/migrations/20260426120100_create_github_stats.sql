-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

CREATE TABLE github_stats (
  id BIGSERIAL PRIMARY KEY,
  since TIMESTAMPTZ NOT NULL,
  repos_scanned INTEGER NOT NULL,
  unique_owners INTEGER NOT NULL,
  unique_committers INTEGER NOT NULL,
  collected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_github_stats_collected_at ON github_stats (collected_at DESC);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP INDEX idx_github_stats_collected_at;
DROP TABLE github_stats;
