# AI Cheerleader Analytics Backend Endpoints
# Add these endpoints to your existing backend API

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional, Dict, Any
from datetime import datetime
import uuid

router = APIRouter(prefix="/ai-cheerleader", tags=["ai-cheerleader-analytics"])

class InteractionLog(BaseModel):
    session_id: str
    user_id: str
    personality: str
    trigger_type: str
    openai_prompt: str
    openai_response: str
    elevenlabs_voice_id: Optional[str] = None
    session_context: Dict[str, Any]
    location_context: Optional[Dict[str, Any]] = None
    trigger_data: Optional[Dict[str, Any]] = None
    explicit_content_enabled: bool = False
    user_gender: Optional[str] = None
    user_prefer_metric: Optional[bool] = None
    generation_time_ms: Optional[int] = None
    synthesis_success: Optional[bool] = True
    synthesis_time_ms: Optional[int] = None
    message_length: int
    word_count: int
    has_location_reference: bool = False
    has_weather_reference: bool = False
    has_personal_reference: bool = False

class PersonalitySelection(BaseModel):
    user_id: str
    session_id: str
    personality: str
    explicit_content_enabled: bool = False
    session_duration_planned_minutes: Optional[int] = None
    session_distance_planned_km: Optional[float] = None
    ruck_weight_kg: Optional[float] = None
    user_total_rucks: Optional[int] = 0
    user_total_distance_km: Optional[float] = 0

class SessionStart(BaseModel):
    session_id: str
    user_id: str
    personality: str
    explicit_content_enabled: bool = False
    ai_enabled_at_start: bool = True

class SessionMetricsUpdate(BaseModel):
    total_interactions: Optional[int] = None
    total_triggers_fired: Optional[int] = None
    total_successful_syntheses: Optional[int] = None
    total_failed_syntheses: Optional[int] = None
    avg_generation_time_ms: Optional[int] = None
    avg_synthesis_time_ms: Optional[int] = None
    session_completed: Optional[bool] = None
    ai_disabled_during_session: Optional[bool] = None
    ai_disabled_at: Optional[datetime] = None

@router.post("/interactions")
async def log_interaction(interaction: InteractionLog, db = Depends(get_db)):
    """Log an AI cheerleader interaction for analytics"""
    try:
        query = """
        INSERT INTO ai_cheerleader_interactions (
            session_id, user_id, personality, trigger_type, openai_prompt, openai_response,
            elevenlabs_voice_id, session_context, location_context, trigger_data,
            explicit_content_enabled, user_gender, user_prefer_metric,
            generation_time_ms, synthesis_success, synthesis_time_ms,
            message_length, word_count, has_location_reference, 
            has_weather_reference, has_personal_reference
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21)
        """
        
        await db.execute(
            query,
            interaction.session_id, interaction.user_id, interaction.personality,
            interaction.trigger_type, interaction.openai_prompt, interaction.openai_response,
            interaction.elevenlabs_voice_id, interaction.session_context, interaction.location_context,
            interaction.trigger_data, interaction.explicit_content_enabled, interaction.user_gender,
            interaction.user_prefer_metric, interaction.generation_time_ms, interaction.synthesis_success,
            interaction.synthesis_time_ms, interaction.message_length, interaction.word_count,
            interaction.has_location_reference, interaction.has_weather_reference, interaction.has_personal_reference
        )
        
        return {"status": "success", "message": "Interaction logged successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to log interaction: {str(e)}")

@router.post("/personality-selections")
async def log_personality_selection(selection: PersonalitySelection, db = Depends(get_db)):
    """Log personality selection for analytics"""
    try:
        query = """
        INSERT INTO ai_personality_selections (
            user_id, session_id, personality, explicit_content_enabled,
            session_duration_planned_minutes, session_distance_planned_km, ruck_weight_kg,
            user_total_rucks, user_total_distance_km
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        """
        
        await db.execute(
            query,
            selection.user_id, selection.session_id, selection.personality,
            selection.explicit_content_enabled, selection.session_duration_planned_minutes,
            selection.session_distance_planned_km, selection.ruck_weight_kg,
            selection.user_total_rucks, selection.user_total_distance_km
        )
        
        return {"status": "success", "message": "Personality selection logged successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to log personality selection: {str(e)}")

@router.post("/sessions")
async def log_session_start(session: SessionStart, db = Depends(get_db)):
    """Log AI cheerleader session start"""
    try:
        query = """
        INSERT INTO ai_cheerleader_sessions (
            session_id, user_id, personality, explicit_content_enabled, ai_enabled_at_start
        ) VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (session_id) DO NOTHING
        """
        
        await db.execute(
            query,
            session.session_id, session.user_id, session.personality,
            session.explicit_content_enabled, session.ai_enabled_at_start
        )
        
        return {"status": "success", "message": "Session start logged successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to log session start: {str(e)}")

@router.patch("/sessions/{session_id}")
async def update_session_metrics(session_id: str, metrics: SessionMetricsUpdate, db = Depends(get_db)):
    """Update AI cheerleader session metrics"""
    try:
        # Build dynamic update query
        update_fields = []
        values = []
        param_count = 1
        
        for field, value in metrics.dict(exclude_unset=True).items():
            if value is not None:
                update_fields.append(f"{field} = ${param_count}")
                values.append(value)
                param_count += 1
        
        if not update_fields:
            return {"status": "success", "message": "No fields to update"}
        
        query = f"""
        UPDATE ai_cheerleader_sessions 
        SET {', '.join(update_fields)}, updated_at = CURRENT_TIMESTAMP
        WHERE session_id = ${param_count}
        """
        values.append(session_id)
        
        await db.execute(query, *values)
        
        return {"status": "success", "message": "Session metrics updated successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update session metrics: {str(e)}")

@router.get("/analytics")
async def get_analytics(
    user_id: Optional[str] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    personality: Optional[str] = None,
    db = Depends(get_db)
):
    """Get analytics data (admin/user-specific)"""
    try:
        # Base query for analytics
        where_conditions = []
        params = []
        param_count = 1
        
        if user_id:
            where_conditions.append(f"user_id = ${param_count}")
            params.append(user_id)
            param_count += 1
            
        if start_date:
            where_conditions.append(f"created_at >= ${param_count}")
            params.append(start_date)
            param_count += 1
            
        if end_date:
            where_conditions.append(f"created_at <= ${param_count}")
            params.append(end_date)
            param_count += 1
            
        if personality:
            where_conditions.append(f"personality = ${param_count}")
            params.append(personality)
            param_count += 1
        
        where_clause = "WHERE " + " AND ".join(where_conditions) if where_conditions else ""
        
        # Personality usage statistics
        personality_query = f"""
        SELECT 
            personality,
            COUNT(*) as usage_count,
            COUNT(DISTINCT user_id) as unique_users,
            AVG(generation_time_ms) as avg_generation_time,
            AVG(message_length) as avg_message_length
        FROM ai_cheerleader_interactions 
        {where_clause}
        GROUP BY personality
        ORDER BY usage_count DESC
        """
        
        personalities = await db.fetch(personality_query, *params)
        
        # Trigger type statistics
        trigger_query = f"""
        SELECT 
            trigger_type,
            COUNT(*) as trigger_count,
            AVG(generation_time_ms) as avg_generation_time
        FROM ai_cheerleader_interactions 
        {where_clause}
        GROUP BY trigger_type
        ORDER BY trigger_count DESC
        """
        
        triggers = await db.fetch(trigger_query, *params)
        
        # Message content analysis
        content_query = f"""
        SELECT 
            COUNT(*) as total_interactions,
            SUM(CASE WHEN has_location_reference THEN 1 ELSE 0 END) as location_references,
            SUM(CASE WHEN has_weather_reference THEN 1 ELSE 0 END) as weather_references,
            SUM(CASE WHEN has_personal_reference THEN 1 ELSE 0 END) as personal_references,
            AVG(word_count) as avg_word_count,
            AVG(synthesis_time_ms) as avg_synthesis_time
        FROM ai_cheerleader_interactions 
        {where_clause}
        """
        
        content_stats = await db.fetchrow(content_query, *params)
        
        return {
            "personality_usage": [dict(row) for row in personalities],
            "trigger_statistics": [dict(row) for row in triggers],
            "content_analysis": dict(content_stats) if content_stats else {},
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch analytics: {str(e)}")

# Usage tracking for feature adoption
@router.get("/adoption-metrics")
async def get_adoption_metrics(db = Depends(get_db)):
    """Get AI cheerleader feature adoption metrics"""
    try:
        query = """
        SELECT 
            DATE_TRUNC('day', created_at) as date,
            COUNT(DISTINCT user_id) as daily_active_users,
            COUNT(*) as total_interactions,
            COUNT(DISTINCT session_id) as sessions_with_ai
        FROM ai_cheerleader_interactions
        WHERE created_at >= NOW() - INTERVAL '30 days'
        GROUP BY DATE_TRUNC('day', created_at)
        ORDER BY date DESC
        """
        
        adoption_data = await db.fetch(query)
        
        return {
            "daily_metrics": [dict(row) for row in adoption_data]
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch adoption metrics: {str(e)}")
