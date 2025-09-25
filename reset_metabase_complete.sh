#!/bin/bash

echo "WARNING: This will reset your entire Metabase installation!"
echo "You will lose all dashboards, queries, and configurations."
echo "Press Ctrl+C to cancel, or any key to continue..."
read -n 1

echo "Stopping Metabase..."
docker stop metabase

echo "Backing up current data..."
mv /Users/rory/RuckingApp/metabase-data /Users/rory/RuckingApp/metabase-data.backup.$(date +%Y%m%d_%H%M%S)

echo "Creating fresh data directory..."
mkdir -p /Users/rory/RuckingApp/metabase-data

echo "Starting fresh Metabase..."
docker start metabase

echo "Waiting for Metabase to initialize..."
sleep 20

echo "=========================="
echo "Metabase has been reset!"
echo "=========================="
echo "Open http://localhost:3000 in your browser"
echo "You'll need to set up a new admin account"
echo ""
echo "Your old data is backed up in metabase-data.backup.*"
echo "To restore it, stop metabase and swap the directories back"