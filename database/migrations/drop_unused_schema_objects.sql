-- Remove empty, unused schema objects (replaced by runtime tables / live queries).
-- Safe to run on Supabase: feedback, user_history, daily_analytics, barber_performance
-- were never written to by the application. queue_display view was never queried.

BEGIN;

DROP VIEW IF EXISTS queue_display;

DROP TABLE IF EXISTS feedback;
DROP TABLE IF EXISTS user_history;
DROP TABLE IF EXISTS daily_analytics;
DROP TABLE IF EXISTS barber_performance;

COMMIT;
