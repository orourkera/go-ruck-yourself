from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase

# Define SQLAlchemy base
class Base(DeclarativeBase):
    pass

# Create the database instance
db = SQLAlchemy(model_class=Base) 