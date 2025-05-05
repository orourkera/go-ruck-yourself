from sqlalchemy.orm import Session
from .models import db

def get_db():
    db_session = db.session()
    try:
        yield db_session
    finally:
        db_session.close()
