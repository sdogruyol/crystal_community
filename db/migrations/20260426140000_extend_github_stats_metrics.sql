-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

ALTER TABLE github_stats
  ADD COLUMN repos_pushed_last_30d INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN repos_created_last_30d INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN total_stars BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN stars_bucket_0 INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN stars_bucket_1_10 INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN stars_bucket_11_100 INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN stars_bucket_101_1000 INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN stars_bucket_1001_plus INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN repos_owner_user INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN repos_owner_org INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN top_topics_json TEXT NOT NULL DEFAULT '[]';

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

ALTER TABLE github_stats
  DROP COLUMN repos_pushed_last_30d,
  DROP COLUMN repos_created_last_30d,
  DROP COLUMN total_stars,
  DROP COLUMN stars_bucket_0,
  DROP COLUMN stars_bucket_1_10,
  DROP COLUMN stars_bucket_11_100,
  DROP COLUMN stars_bucket_101_1000,
  DROP COLUMN stars_bucket_1001_plus,
  DROP COLUMN repos_owner_user,
  DROP COLUMN repos_owner_org,
  DROP COLUMN top_topics_json;
