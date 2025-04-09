# Rucking App

A mobile application for tracking rucking workouts, built with Flutter.

## Overview

The Rucking App helps users track their rucking sessions, including distance, pace, calories burned, and elevation changes. Users can create, start, pause, and complete rucking sessions, as well as view their historical data and statistics.

## Features

- User authentication (registration, login, profile management)
- Create and manage rucking sessions
- Real-time GPS tracking during sessions
- Session statistics (distance, elevation, calories burned, etc.)
- Historical data visualization (weekly, monthly, yearly summaries)
- Integration with health apps (Apple Health, Google Fit)
- Offline support
- Dark and light theme

## Architecture

The app follows a clean architecture approach with the following layers:

- **Presentation Layer**: UI components, screens, and BLoC for state management
- **Domain Layer**: Business logic, use cases, and repository interfaces
- **Data Layer**: Repository implementations, data sources, and models

## Project Structure

```
lib/
├── core/
│   ├── api/             # API client, interceptors
│   ├── config/          # App configuration
│   ├── models/          # Shared models
│   ├── services/        # Core services
│   └── utils/           # Utilities and helpers
├── features/
│   ├── auth/            # Authentication feature
│   ├── profile/         # User profile
│   ├── ruck_session/    # Session tracking
│   ├── statistics/      # Stats and history
│   └── health_sync/     # Health app integration
└── shared/
    ├── widgets/         # Reusable widgets
    └── theme/           # App theme
```

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Android Studio or VS Code with Flutter extension
- iOS development tools (for iOS deployment)

### Installation

1. Clone the repository
   ```
   git clone https://github.com/yourusername/rucking_app.git
   ```

2. Navigate to the project directory
   ```
   cd rucking_app
   ```

3. Install dependencies
   ```
   flutter pub get
   ```

4. Run the app
   ```
   flutter run
   ```

## Backend Integration

This app connects to a RESTful API backend. The API documentation can be found in the backend repository.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 