-- Step 4: Enable RLS and create policies for user_device_tokens table
ALTER TABLE user_device_tokens ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to insert their own device tokens
CREATE POLICY "Users can insert their own device tokens" ON user_device_tokens
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Policy to allow users to view their own device tokens
CREATE POLICY "Users can view their own device tokens" ON user_device_tokens
    FOR SELECT USING (auth.uid() = user_id);

-- Policy to allow users to update their own device tokens
CREATE POLICY "Users can update their own device tokens" ON user_device_tokens
    FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Policy to allow users to delete their own device tokens
CREATE POLICY "Users can delete their own device tokens" ON user_device_tokens
    FOR DELETE USING (auth.uid() = user_id);
