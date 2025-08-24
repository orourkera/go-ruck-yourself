from marshmallow import Schema, fields, validate
from datetime import datetime
from pydantic import BaseModel

class UserSchema(Schema):
    class Meta:
        unknown = "exclude"  # Ignore unknown fields gracefully
    """Schema for validating user data"""
    id = fields.Int(dump_only=True)
    username = fields.Str(validate=validate.Length(min=3, max=64))  # Not required for registration
    email = fields.Email(required=True)
    password = fields.Str(load_only=True, validate=validate.Length(min=8))
    weight_kg = fields.Float(validate=validate.Range(min=20, max=500))
    created_at = fields.DateTime(dump_only=True)
    updated_at = fields.DateTime(dump_only=True)

class LoginSchema(Schema):
    """Schema for validating login data"""
    email = fields.Email(required=True)
    password = fields.Str(required=True, validate=validate.Length(min=1))

class AuthResponseSchema(Schema):
    """Schema for auth response data"""
    token = fields.Str(required=True)
    user = fields.Nested(UserSchema, required=True)

class SessionSchema(Schema):
    """Schema for validating rucking session data"""
    id = fields.Int(dump_only=True)
    user_id = fields.Int(required=True)
    ruck_weight_kg = fields.Float(required=True, validate=validate.Range(min=0, max=100))
    start_time = fields.DateTime(dump_only=True)
    end_time = fields.DateTime(dump_only=True)
    duration_seconds = fields.Int(dump_only=True)
    paused_duration_seconds = fields.Int(dump_only=True)
    status = fields.Str(validate=validate.OneOf(['created', 'active', 'paused', 'completed']))
    distance_km = fields.Float(dump_only=True)
    elevation_gain_m = fields.Float(dump_only=True)
    elevation_loss_m = fields.Float(dump_only=True)
    calories_burned = fields.Float(dump_only=True)
    planned_duration_minutes = fields.Int(required=False, allow_none=True)
    created_at = fields.DateTime(dump_only=True)
    updated_at = fields.DateTime(dump_only=True)

class SessionLocationUpdateSchema(Schema):
    """Schema for validating session location updates"""
    latitude = fields.Float(required=True)
    longitude = fields.Float(required=True)
    elevation_meters = fields.Float(required=True)
    timestamp = fields.DateTime(required=True)
    accuracy_meters = fields.Float(required=True)
    elevation_gain_meters = fields.Float(required=False, allow_none=True)
    elevation_loss_meters = fields.Float(required=False, allow_none=True)

class LocationPointSchema(Schema):
    """Schema for validating location point data"""
    id = fields.Int(dump_only=True)
    session_id = fields.Int(dump_only=True)
    latitude = fields.Float(required=True, validate=validate.Range(min=-90, max=90))
    longitude = fields.Float(required=True, validate=validate.Range(min=-180, max=180))
    altitude = fields.Float()
    timestamp = fields.DateTime(dump_only=True)

class SessionReviewSchema(Schema):
    """Schema for validating session review data"""
    id = fields.Int(dump_only=True)
    session_id = fields.Int(dump_only=True)
    rating = fields.Int(required=True, validate=validate.Range(min=1, max=5))
    notes = fields.Str()
    created_at = fields.DateTime(dump_only=True)
    updated_at = fields.DateTime(dump_only=True)

class StatisticsSchema(Schema):
    """Schema for validating statistics data"""
    total_distance_km = fields.Float()
    total_elevation_gain_m = fields.Float()
    total_calories_burned = fields.Float()
    average_distance_km = fields.Float()
    session_count = fields.Int()
    total_duration_seconds = fields.Int()
    monthly_breakdown = fields.List(fields.Dict(), dump_only=True)

class AppleHealthWorkoutSchema(Schema):
    """Schema for validating Apple Health workout data"""
    workoutActivityType = fields.Str(required=True)
    startDate = fields.DateTime(required=True)
    endDate = fields.DateTime(required=True)
    duration = fields.Float(required=True)
    distance = fields.Float(required=True)
    elevationAscended = fields.Float()
    metadata = fields.Dict()
    route = fields.List(fields.Dict())

class AppleHealthSyncSchema(Schema):
    """Schema for validating Apple Health sync data"""
    workouts = fields.List(fields.Nested(AppleHealthWorkoutSchema), required=True)

class AppleHealthStatusSchema(Schema):
    """Schema for validating Apple Health integration status"""
    integration_enabled = fields.Bool(required=True)
    metrics_to_sync = fields.List(fields.Str(), validate=validate.ContainsOnly(['workouts', 'distance', 'elevation']))
    last_sync_time = fields.DateTime(allow_none=True)

# ==============================
# Custom Goals & AI Copy Schemas
# ==============================

SUPPORTED_METRICS = [
    'distance_km_total',
    'session_count',
    'streak_days',
    'elevation_gain_m_total',
    'duration_minutes_total',
    'steps_total',
    'power_points_total',
    'load_kg_min_sessions',
]

SUPPORTED_UNITS = ['km', 'mi', 'minutes', 'steps', 'm', 'kg', 'points']
SUPPORTED_WINDOWS = ['7d', '30d', 'weekly', 'monthly', 'until_deadline']


class GoalDraftSchema(Schema):
    class Meta:
        unknown = "exclude"

    # Draft produced by AI parser before creation/confirmation
    title = fields.Str(validate=validate.Length(min=1, max=200))
    description = fields.Str()
    metric = fields.Str(required=True, validate=validate.OneOf(SUPPORTED_METRICS))
    target_value = fields.Float(required=True, validate=validate.Range(min=0))
    unit = fields.Str(required=True, validate=validate.OneOf(SUPPORTED_UNITS))
    window = fields.Str(allow_none=True, validate=validate.OneOf(SUPPORTED_WINDOWS))
    constraints_json = fields.Dict(allow_none=True)
    start_at = fields.DateTime(allow_none=True)
    end_at = fields.DateTime(allow_none=True)
    deadline_at = fields.DateTime(allow_none=True)


class GoalCreateSchema(Schema):
    class Meta:
        unknown = "exclude"

    # Payload client/backend uses to create a goal from a draft
    title = fields.Str(required=True, validate=validate.Length(min=1, max=200))
    description = fields.Str(allow_none=True)
    metric = fields.Str(required=True, validate=validate.OneOf(SUPPORTED_METRICS))
    target_value = fields.Float(required=True, validate=validate.Range(min=0))
    unit = fields.Str(required=True, validate=validate.OneOf(SUPPORTED_UNITS))
    window = fields.Str(allow_none=True, validate=validate.OneOf(SUPPORTED_WINDOWS))
    constraints_json = fields.Dict(allow_none=True)
    start_at = fields.DateTime(allow_none=True)
    end_at = fields.DateTime(allow_none=True)
    deadline_at = fields.DateTime(allow_none=True)


class NotificationCopySchema(Schema):
    class Meta:
        unknown = "exclude"

    title = fields.Str(required=True, validate=validate.Length(max=30))
    body = fields.Str(required=True, validate=validate.Length(max=140))
    category = fields.Str(required=True, validate=validate.OneOf([
        'behind_pace', 'on_track', 'milestone', 'completion', 'deadline_urgent', 'inactivity'
    ]))
    uses_emoji = fields.Bool(required=True)

class HeartRateSampleIn(BaseModel):
    timestamp: datetime
    bpm: int

# Create schema instances
apple_health_sync_schema = AppleHealthSyncSchema()
apple_health_status_schema = AppleHealthStatusSchema()
goal_draft_schema = GoalDraftSchema()
goal_create_schema = GoalCreateSchema()
notification_copy_schema = NotificationCopySchema()