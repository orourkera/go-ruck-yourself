#!/bin/bash

# Update all imports to use the consolidated auth service
cd /Users/rory/RuckingApp/rucking_app

# Files to update
files=(
  "lib/core/security/token_refresh_interceptor.dart"
  "lib/core/security/security_timeout_widget.dart"
  "lib/core/services/avatar_service.dart"
  "lib/core/services/dau_tracking_service.dart"
  "lib/core/services/watch_service.dart"
  "lib/core/services/enhanced_api_client.dart"
  "lib/core/services/rucking_api_handler.dart"
  "lib/features/planned_rucks/presentation/bloc/route_import_bloc.dart"
  "lib/features/auth/data/repositories/auth_repository_impl.dart"
  "lib/features/ruck_session/data/repositories/session_repository.dart"
  "lib/features/ruck_session/presentation/bloc/managers/location_tracking_manager.dart"
  "lib/features/ruck_session/presentation/bloc/managers/session_lifecycle_manager.dart"
  "lib/features/ruck_session/presentation/bloc/managers/photo_manager.dart"
  "lib/features/ruck_session/presentation/bloc/active_session_coordinator.dart"
  "lib/features/ruck_session/presentation/bloc/active_session_bloc.dart"
  "lib/features/ruck_buddies/data/datasources/ruck_buddies_remote_datasource.dart"
  "lib/features/social/data/repositories/social_repository.dart"
)

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo "Updating: $file"
    # Replace old imports with new consolidated import
    sed -i '' "s|import 'package:rucking_app/core/services/auth_service\.dart';|import 'package:rucking_app/core/services/auth_service_consolidated.dart';|g" "$file"
    sed -i '' "s|import 'package:rucking_app/core/services/auth_service_wrapper\.dart';|import 'package:rucking_app/core/services/auth_service_consolidated.dart';|g" "$file"

    # Also update relative imports
    sed -i '' "s|import '.*auth_service\.dart';|import 'package:rucking_app/core/services/auth_service_consolidated.dart';|g" "$file"
    sed -i '' "s|import '.*auth_service_wrapper\.dart';|import 'package:rucking_app/core/services/auth_service_consolidated.dart';|g" "$file"
  fi
done

echo "All imports updated successfully!"