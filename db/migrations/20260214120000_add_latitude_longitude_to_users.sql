-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

ALTER TABLE users ADD COLUMN latitude DOUBLE PRECISION;
ALTER TABLE users ADD COLUMN longitude DOUBLE PRECISION;

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

ALTER TABLE users DROP COLUMN latitude;
ALTER TABLE users DROP COLUMN longitude;
