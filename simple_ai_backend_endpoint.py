# Simple AI Cheerleader Logging Endpoint
# Add this to your existing backend API

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/ai-cheerleader", tags=["ai-cheerleader"])

class SimpleLogRequest(BaseModel):
    session_id: str
    personality: str
    openai_response: str

@router.post("/log")
async def log_ai_response(log_request: SimpleLogRequest, db = Depends(get_db)):
    """Log AI cheerleader response - simple 3 column table"""
    try:
        query = """
        INSERT INTO ai_cheerleader_logs (session_id, personality, openai_response)
        VALUES ($1, $2, $3)
        """
        
        await db.execute(
            query,
            log_request.session_id,
            log_request.personality, 
            log_request.openai_response
        )
        
        return {"status": "success", "message": "AI response logged"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to log response: {str(e)}")
