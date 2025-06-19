-- Migration: Fix user_id foreign keys on event-related tables to reference the public "users" table instead of "auth.users"
-- Author: Cascade AI 2025-06-19
-- NOTE: All tables still pointing at auth.users will break the lateral join that the API uses
--       to fetch the related user object ( username, avatar_url ).
--       This script recreates those foreign-keys to point at the correct public.users table.

-- Helper: drop FK if it exists
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT conname, conrelid::regclass AS rel
        FROM pg_constraint
        WHERE conname IN (
            'event_participants_user_id_fkey',
            'event_participant_progress_user_id_fkey',
            'event_comments_user_id_fkey',
            'events_creator_user_id_fkey'
        ) LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I', r.rel, r.conname);
    END LOOP;
END $$;

-- event_participants.user_id → "user"(id)
ALTER TABLE IF EXISTS event_participants
    ADD CONSTRAINT event_participants_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE;

-- event_participant_progress.user_id → "user"(id)
ALTER TABLE IF EXISTS event_participant_progress
    ADD CONSTRAINT event_participant_progress_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE;

-- event_comments.user_id → "user"(id)
ALTER TABLE IF EXISTS event_comments
    ADD CONSTRAINT event_comments_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE;

-- events.creator_user_id → "user"(id)
ALTER TABLE IF EXISTS events
    ADD CONSTRAINT events_creator_user_id_fkey
    FOREIGN KEY (creator_user_id) REFERENCES "user"(id) ON DELETE SET NULL;

-- Verify
-- SELECT table_name, constraint_name, pg_get_constraintdef(c.oid)
-- FROM information_schema.table_constraints tc
-- JOIN pg_constraint c ON c.conname = tc.constraint_name
-- WHERE constraint_name LIKE '%user_id_fkey' AND table_name LIKE 'event%';
