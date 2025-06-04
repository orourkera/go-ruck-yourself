# RuckClub API & Data Model Consistency Report

## Executive Summary

After reviewing the existing API endpoints (`api_endpoints.md`), data model (`DATA_MODEL_REFERENCE.md`), and the new RuckClub implementation plan, I've identified several areas where adjustments are needed to ensure consistency with the existing codebase patterns.

## Key Findings & Recommendations

### 1. API Endpoint Naming Conventions

**Existing Pattern:**
- URLs use `/api/` prefix for most endpoints
- Hyphenated names in URLs (e.g., `/api/ruck-photos`, `/api/ruck-buddies`)
- Resource IDs in path: `/api/rucks/<int:ruck_id>`
- No `/api/` prefix for some newer endpoints (e.g., `/achievements/*`)

**RuckClub Implementation Issues:**
- The PRD doesn't specify URL paths, only resource names
- Need to follow hyphenated naming convention

**Recommended RuckClub Endpoints:**
```
# Club Management
/api/clubs                              # GET (list), POST (create)
/api/clubs/<uuid:club_id>               # GET, PUT, DELETE
/api/clubs/<uuid:club_id>/members       # GET, POST
/api/clubs/<uuid:club_id>/members/<uuid:user_id>  # DELETE
/api/clubs/<uuid:club_id>/invites       # POST

# Club Rucks
/api/club-rucks                         # GET (list), POST (create)
/api/club-rucks/<uuid:ruck_id>          # GET, PUT
/api/club-rucks/<uuid:ruck_id>/lobby    # POST (join), DELETE (leave)
/api/club-rucks/<uuid:ruck_id>/participants  # GET

# Scheduled Rucks
/api/scheduled-rucks                    # GET (list), POST (create)
/api/scheduled-rucks/<uuid:scheduled_id> # GET, PUT, DELETE
/api/scheduled-rucks/<uuid:scheduled_id>/rsvp  # POST, DELETE
```

### 2. Database Naming Conventions

**Existing Pattern:**
- Table names: Singular form (e.g., `ruck_session`, not `ruck_sessions`)
- Column names: Snake_case (e.g., `user_id`, `ruck_weight_kg`)
- Timestamps: Mix of `timestamp with time zone` and `timestamp without time zone`
- Foreign keys: Named as `<entity>_id` (e.g., `user_id`, `session_id`)

**RuckClub Implementation Issues:**
- ✅ Column naming follows snake_case correctly
- ❌ Table names use plural form (should be singular)
- ✅ Foreign key naming is consistent
- ⚠️  Timestamp types should be reviewed for consistency

**Corrected Table Names:**
```sql
-- Change from plural to singular
clubs → club
club_members → club_member
club_rucks → club_ruck
club_ruck_participants → club_ruck_participant  
scheduled_rucks → scheduled_ruck
```

### 3. API Response Format

**Existing Pattern:**
```json
// Session response includes nested data
{
  "id": "uuid",
  "user_id": "uuid",
  "distance_km": 5.0,
  "splits": [...],  // Nested array
  "photos": [...]   // Nested array
}
```

**RuckClub Should Follow:**
```json
// Club response with nested members
{
  "id": "uuid",
  "title": "Morning Ruckers",
  "admin_id": "uuid",
  "members": [...],      // Nested array
  "current_ruck": {...}  // Nested object if active
}
```

### 4. Authentication & Authorization

**Existing Pattern:**
- JWT Bearer tokens in Authorization header
- User context available in `g.user`
- Supabase RLS for database-level security
- Custom permission checks in Flask resources

**RuckClub Implementation:**
- ✅ RLS policies are well-defined
- ✅ JWT authentication assumed
- ⚠️  Need to add Flask-level permission checks for admin operations

### 5. Backend File Organization

**Existing Pattern:**
```
/RuckTracker/api/
├── achievements.py      # All achievement-related resources
├── ruck.py             # Core ruck session resources
├── ruck_photos_resource.py
├── ruck_likes_resource.py
└── ruck_buddies.py
```

**RuckClub Should Use:**
```
/RuckTracker/api/
├── clubs.py            # Club + member management
├── club_rucks.py       # Club ruck sessions
└── scheduled_rucks.py  # Scheduled ruck events
```

### 6. Specific Data Model Adjustments

**Power Points Field:**
- Add to `ruck_session` table as calculated column:
```sql
ALTER TABLE ruck_session 
ADD COLUMN power_points NUMERIC GENERATED ALWAYS AS 
  (ruck_weight_kg * distance_km * (elevation_gain_m / 1000.0)) STORED;
```

**Club Statistics:**
- Consider using JSONB for flexible stats storage (matches existing pattern)
- Add indexes for common queries

### 7. Flutter Integration Points

**Existing Pattern:**
- Repository pattern for data access
- BLoC for state management
- Models with `fromJson`/`toJson` methods
- Consistent error handling

**RuckClub Should:**
- Follow same repository/BLoC pattern
- Ensure models match API response format exactly
- Use existing `ApiException` patterns

## Implementation Priority

1. **Immediate Changes Needed:**
   - Rename database tables to singular form
   - Update Flask resource URLs to use hyphens
   - Add `/api/` prefix to endpoints

2. **Before Backend Implementation:**
   - Define exact API request/response formats
   - Add power_points to ruck_session table
   - Create migration scripts with proper rollback

3. **During Implementation:**
   - Follow existing error response format
   - Use consistent logging patterns
   - Add comprehensive RLS tests

## Conclusion

The RuckClub implementation plan is well-structured but needs minor adjustments to align with existing conventions. The main changes are:
- Database table names (plural → singular)
- API endpoint paths (add hyphens and `/api/` prefix)
- Ensure consistent timestamp types
- Follow existing response formats

These changes will ensure the new feature integrates seamlessly with the existing codebase and maintains consistency for developers and the Flutter app.
