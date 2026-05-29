-- Enable Realtime for tables that need live subscriptions.
-- Supabase auto-creates the supabase_realtime publication; these statements
-- are safe to run multiple times (ADD TABLE on an already-member table is a
-- no-op in PostgreSQL >= 15; Supabase wraps earlier versions the same way).
ALTER PUBLICATION supabase_realtime ADD TABLE public.matches;
ALTER PUBLICATION supabase_realtime ADD TABLE public.match_events;
ALTER PUBLICATION supabase_realtime ADD TABLE public.predictions;
