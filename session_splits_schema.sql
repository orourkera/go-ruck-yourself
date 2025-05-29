-- Session Splits Table
-- Table to store individual kilometer/mile splits during ruck sessions

-- Create sequence for session_splits first (before table creation)
CREATE SEQUENCE IF NOT EXISTS session_splits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE session_splits (
    id integer NOT NULL DEFAULT nextval('session_splits_id_seq'::regclass),
    session_id integer NOT NULL,
    split_number integer NOT NULL,
    split_distance_km numeric NOT NULL,
    split_duration_seconds integer NOT NULL,
    total_distance_km numeric NOT NULL,
    total_duration_seconds integer NOT NULL,
    split_timestamp timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    
    CONSTRAINT session_splits_pkey PRIMARY KEY (id),
    CONSTRAINT session_splits_session_id_fkey FOREIGN KEY (session_id) 
        REFERENCES ruck_session(id) ON DELETE CASCADE,
    CONSTRAINT session_splits_split_number_positive CHECK (split_number > 0),
    CONSTRAINT session_splits_distance_positive CHECK (split_distance_km > 0),
    CONSTRAINT session_splits_duration_positive CHECK (split_duration_seconds > 0),
    CONSTRAINT session_splits_unique_split UNIQUE (session_id, split_number)
);

-- Indexes for performance
CREATE INDEX idx_session_splits_session_id ON session_splits(session_id);
CREATE INDEX idx_session_splits_split_timestamp ON session_splits(split_timestamp);

-- RLS Policies for session_splits
ALTER TABLE session_splits ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see splits from their own sessions
CREATE POLICY "Users can view their own session splits" ON session_splits
    FOR SELECT USING (
        session_id IN (
            SELECT id FROM ruck_session WHERE user_id = auth.uid()
        )
    );

-- Policy: Users can only insert splits for their own sessions  
CREATE POLICY "Users can insert splits for their own sessions" ON session_splits
    FOR INSERT WITH CHECK (
        session_id IN (
            SELECT id FROM ruck_session WHERE user_id = auth.uid()
        )
    );

-- Policy: Users can only update splits from their own sessions
CREATE POLICY "Users can update their own session splits" ON session_splits
    FOR UPDATE USING (
        session_id IN (
            SELECT id FROM ruck_session WHERE user_id = auth.uid()
        )
    );

-- Policy: Users can only delete splits from their own sessions
CREATE POLICY "Users can delete their own session splits" ON session_splits
    FOR DELETE USING (
        session_id IN (
            SELECT id FROM ruck_session WHERE user_id = auth.uid()
        )
    );

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_session_splits_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to automatically update updated_at on row updates
CREATE TRIGGER update_session_splits_updated_at
    BEFORE UPDATE ON session_splits
    FOR EACH ROW
    EXECUTE FUNCTION update_session_splits_updated_at();
