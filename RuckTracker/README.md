# Rucking App API

A Flask-based RESTful API backend for a rucking app that provides endpoints for tracking, analyzing, and storing workout data.

## Features

- **User Management**: Create and manage user accounts with profile data and authentication
- **JWT Authentication**: Secure authentication system using JSON Web Tokens
- **Workout Tracking**: Track rucking sessions with location, distance, elevation, and performance metrics
- **Statistics & Analysis**: View comprehensive statistics and progress over time (weekly, monthly, yearly)
- **Session Reviews**: Rate and review completed sessions with notes for future reference
- **Calorie Calculations**: Calculate calories burned based on user weight, ruck weight, distance, and elevation
- **Apple Health Integration**: Sync workout data with Apple Health for a comprehensive fitness overview

## API Endpoints

### Authentication
- `POST /api/auth/login` - Login with email and password
- `POST /api/users/register` - Register a new user
- `GET /api/users/profile` - Get the current user's profile (authenticated)
- `PUT /api/users/profile` - Update the current user's profile (authenticated)

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
- Python 3.11+
- Flask
- SQLAlchemy
- SQLite (local development) or PostgreSQL (production)
- PyJWT for authentication

### Installation

1. Clone the repository
   ```
   git clone https://github.com/orourkera/go-ruck-yourself.git
   cd RuckTracker
   ```

2. Create and activate a virtual environment
   ```
   python3.11 -m venv venv311
   source venv311/bin/activate
   ```

3. Install dependencies
   ```
   pip install -r requirements.txt
   pip install pyjwt
   ```

4. Set environment variables (optional)
   ```
   export DATABASE_URL=<your-database-connection-string>  # Defaults to SQLite
   export SESSION_SECRET=<your-secret-key>                # For session management
   export JWT_SECRET_KEY=<your-jwt-secret>                # For JWT authentication
   ```

5. Run the server
   ```
   python main.py
   ```

## Project Structure

```
├── api                     # API resources and schemas
│   ├── __init__.py
│   ├── apple_health.py     # Apple Health integration endpoints
│   ├── auth.py             # Authentication endpoints
│   ├── resources.py        # RESTful API resources
│   └── schemas.py          # Data validation schemas
├── data                    # SQLite database directory
│   └── rucktracker.db      # SQLite database file
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

## Authentication

The API uses JWT (JSON Web Token) authentication. To access protected endpoints:

1. Register a user or login to get a token
2. Include the token in the Authorization header of your requests:
   ```
   Authorization: Bearer your-token-here
   ```

## Future Plans

- Create a Flutter frontend to submit to mobile app stores
- Implement real-time location tracking
- Add more detailed metrics and analytics
- Enhance Apple Health integration capabilities