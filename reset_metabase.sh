#!/bin/bash

echo "Stopping Metabase..."
docker stop metabase

echo "Waiting for Metabase to fully stop..."
sleep 5

echo "Starting temporary container to reset password..."
# This creates a bcrypt hash for password 'metabase123'
docker run --rm \
  -v /Users/rory/RuckingApp/metabase-data:/data \
  metabase/metabase \
  bash -c "java -cp /app/metabase.jar org.h2.tools.Shell \
    -url 'jdbc:h2:/data/metabase' \
    -user 'sa' \
    -password '' \
    -sql \"UPDATE core_user SET password_hash = '\$2a\$10\$8IhNVlAGsXKLPnFvhBol3uW2u0eQNy/iAj8zamQIeOU8bQNPcqSe2' WHERE email = 'admin@metabase.local' OR is_superuser = true;\""

echo "Starting Metabase back up..."
docker start metabase

echo "Waiting for Metabase to start..."
sleep 10

echo "Password reset complete!"
echo "Username: admin@metabase.local"
echo "Password: metabase123"
echo "URL: http://localhost:3000"