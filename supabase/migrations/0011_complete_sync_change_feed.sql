-- 0011_complete_sync_change_feed.sql
--
-- Superseded by 20261004010000_cloud_schema_alignment.sql.
--
-- The original contents attached change-feed triggers to tables that no
-- migration created (payment_providers, pos_*, shopping_*, recipes, ...) and
-- declared a trigger function with arguments, so it could not be applied to
-- any database. It was never applied to the hosted project. The tables,
-- policies and triggers it intended now live in the alignment migration.

select 1;
