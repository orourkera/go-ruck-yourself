# Rucking App API

A Flask-based RESTful API backend for a rucking app that provides endpoints for tracking, analyzing, and storing workout data.

## Features

- **User Management**: Create and manage user accounts with profile data and authentication
- **Workout Tracking**: Track rucking sessions with location, distance, elevation, and performance metrics
- **Statistics & Analysis**: View comprehensive statistics and progress over time (weekly, monthly, yearly)
- **Session Reviews**: Rate and review completed sessions with notes for future reference
- **Calorie Calculations**: Calculate calories burned based on user weight, ruck weight, distance, and elevation
- **Apple Health Integration**: Sync workout data with Apple Health for a comprehensive fitness overview

## API Endpoints

### User Management
- `GET /api/users` - List all users
- `POST /api/users` - Create a new user
- `GET /api/users/{id}` - Get a specific user
- `PUT /api/users/{id}` - Update a user
- `DELETE /api/users/{id}` - Delete a user

### Session Management
- `GET /api/sessions` - List all sessions for a user
- `POST /api/sessions` - Create a new session
- `GET /api/sessions/{id}` - Get a specific session
- `PUT /api/sessions/{id}` - Update a session
- `DELETE /api/sessions/{id}` - Delete a session
- `POST /api/sessions/{id}/statistics` - Add location data and update statistics
- `GET /api/sessions/{id}/review` - Get session review
- `POST /api/sessions/{id}/review` - Add/update session review

### Statistics
- `GET /api/statistics/weekly` - Get weekly statistics
- `GET /api/statistics/monthly` - Get monthly statistics
- `GET /api/statistics/yearly` - Get yearly statistics

### Apple Health Integration
- `GET /api/users/{id}/apple-health/status` - Get Apple Health integration status
- `PUT /api/users/{id}/apple-health/status` - Update Apple Health integration settings
- `GET /api/users/{id}/apple-health/sync` - Export workout data in Apple Health format
- `POST /api/users/{id}/apple-health/sync` - Import workout data from Apple Health

## Getting Started

### Prerequisites
- Python 3.7+
- Flask
- SQLAlchemy
- PostgreSQL (recommended for production)

### Installation

1. Clone the repository
   ```
   git clone https://github.com/orourkera/rucking.git
   cd rucking
   ```

2. Install dependencies
   ```
   pip install -r requirements.txt
   ```

3. Set environment variables
   ```
   export DATABASE_URL=<your-database-connection-string>
   export SESSION_SECRET=<your-secret-key>
   ```

4. Run the server
   ```
   gunicorn --bind 0.0.0.0:5000 --reuse-port --reload main:app
   ```

## Project Structure

```
├── api                     # API resources and schemas
│   ├── __init__.py
│   ├── apple_health.py     # Apple Health integration endpoints
│   ├── resources.py        # RESTful API resources
│   └── schemas.py          # Data validation schemas
├── templates               # HTML templates
│   └── index.html          # API documentation page
├── utils                   # Utility functions
│   ├── __init__.py
│   ├── calculations.py     # Calorie and metrics calculations
│   └── location.py         # Location and distance utilities
├── app.py                  # Flask application setup
├── main.py                 # Entry point
├── models.py               # Database models
└── README.md
```

## Future Plans

- Create a Flutter frontend to submit to mobile app stores
- Add user authentication with JWT
- Implement real-time location tracking
- Add more detailed metrics and analytics
- Enhance Apple Health integration capabilities