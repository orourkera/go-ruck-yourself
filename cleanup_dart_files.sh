#!/bin/bash

# Script to clean up Dart files for release candidate
echo "Starting Dart file cleanup for release candidate..."

# Find all Dart files and process them
find rucking_app/lib -name "*.dart" | while read -r file; do
  echo "Processing $file"
  
  # Replace standard debugPrint with categorized logs
  # 1. Add [INFO] tag to regular debugPrint statements
  sed -i '' 's/debugPrint('\''[^[].*'\'')/debugPrint('\''[INFO] \1'\'')/' "$file"
  
  # 2. Remove excessive debug prints that output variable values by commenting them
  sed -i '' 's/\(debugPrint([^E].*\$.*)\);/\/\/ \1;/' "$file"
  
  # 3. Keep error logs with [ERROR] prefix
  
  # 4. Comment out TODO comments with [RC-DEFER]
  sed -i '' 's/\/\/ TODO:/\/\/ [RC-DEFER]:/' "$file"

done

echo "Dart file cleanup complete!"
