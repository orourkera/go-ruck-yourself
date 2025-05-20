# Heart Rate Data Visualization - Implementation Plan

## 1. Overview & Goal

Implement robust heart rate data visualization on the Session Complete and Session Detail screens, providing users with meaningful insights into their cardiovascular performance during completed ruck sessions. Display average and maximum heart rates, along with a historical heart rate graph showing the entire session data, ensuring the implementation is visually engaging and informative. This feature will only display on summary screens after a session is completed - no real-time heart rate visualization is needed.

## 2. Data Model Considerations

### 2.1. Heart Rate Sample Model
Building on the existing `HeartRateSample` entity, ensure it contains:
- `timestamp`: DateTime - When the heart rate was recorded
- `bpm`: int - Heart rate in beats per minute
- `session_id`: String - Foreign key to the ruck session
- (Optional) `source`: String - Source of heart rate data (e.g., "Apple Watch", "Garmin", etc.)

### 2.2. Database Schema Updates
- Ensure the `heart_rate_samples` table in Supabase has appropriate indices for efficient querying:
  - Index on `session_id` for rapid lookups
  - Index on `timestamp` for time-series analysis
  - Composite index on `(session_id, timestamp)` for session-specific time-series queries

### 2.3. Aggregated Heart Rate Metrics
Add heart rate summary fields to the `ruck_session` model:
- `average_heart_rate`: double - Average heart rate during the session
- `max_heart_rate`: int - Maximum heart rate during the session
- `min_heart_rate`: int - Minimum heart rate during the session

## 3. Backend Implementation

### 3.1. Heart Rate Data Handling
- Leverage existing HealthKit integration for heart rate data collection
- Focus on processing and visualization of the collected data
- Optimize data storage and retrieval for efficient visualization

### 3.2. API Endpoints
- Enhance the existing session API to include heart rate data:
  - `POST /ruck_sessions/{id}/heart_rate`: Submit batch of heart rate samples
  - `GET /ruck_sessions/{id}/heart_rate`: Retrieve heart rate samples with optional time range filters
  - `GET /ruck_sessions/{id}/heart_rate/summary`: Get aggregate heart rate metrics

### 3.3. Dependencies
- **FL Chart (fl_chart)**: Already installed in the project (version ^0.64.0)
  - Will be used for heart rate time series visualization
  - Provides LineChart with gradient fills, tooltips, and customizable axes
  - No additional charting libraries needed for implementation

### 3.4. Data Processing
- Implement server-side processing to:
  - Handle data cleaning and smoothing for noisy heart rate signals
  - Calculate aggregate metrics (avg, max, min)

## 4. Frontend Implementation

### 4.1. Data Collection & Real-time Display
- **Active Session Screen Enhancements:**
  - Add current heart rate display with appropriate styling
  - Implement heart rate graph that updates in real-time
  - Add visual indicators for current heart rate intensity

### 4.2. Session Complete Screen Heart Rate Visualization
- **Enhancements to `session_complete_screen.dart`:**
  - Layout and Positioning:
    - Add two heart rate stat tiles to the GridView alongside other stats:
      - Average Heart Rate (Avg HR)
      - Maximum Heart Rate (Max HR)
    - Position the heart rate graph below the stats grid and above the rating section
  - Heart Rate Graph Improvements:
    - Enhanced time series visualization using fl_chart:
      - Smooth curved line with red coloring (AppColors.error)
      - Gradient fill below the line for visual impact
      - Properly labeled axes showing time (minutes) and BPM
      - Interactive tooltip when tapping on data points
    - Chart height of approximately 140-160dp for good visibility
    - Proper padding and spacing around the chart component
  
### 4.3. Session Detail Screen Heart Rate Visualization
- **Enhancements to `session_detail_screen.dart`:**
  - **Layout Restructuring:**
    - Move the rating display to the top section, positioned to the right of the date and time
    - This creates a more balanced header section with key info visible immediately
  - **Heart Rate Section Placement:**
    - Add a dedicated "Heart Rate" section in the scrollable content
    - Position immediately after the existing "Detail stats" section
    - Use consistent section heading styling with other detail sections
  - **Heart Rate Stats Display:**
    - Add only key metrics: Average HR and Maximum HR
    - Use the existing `_buildDetailRow` method for consistent styling
    - Include heart-related icons (Icons.favorite) with appropriate coloring
  - **Heart Rate Graph Implementation:**
    - Add the enhanced graph immediately below the heart rate stats
    - Match the visual styling of other components in the detail view
    - Ensure proper width (match parent) and suitable height (140-160dp)
    - Apply appropriate padding and spacing for visual hierarchy

### 4.4. UI Components
- **Create New Custom Components:**
  - `HeartRateGraph`: Reusable time-series visualization for heart rate data
  - `HeartRateMetricsCard`: Summary card for heart rate statistics (avg, max, min)
  - `HeartRateTooltip`: Interactive tooltip for data point inspection

### 4.4. State Management
- Extend `ActiveSessionBloc` to:
  - Handle heart rate sample collection and temporary storage
  - Calculate real-time heart rate metrics
  - Manage heart rate data submission to backend

- Create new `HeartRateAnalyticsBloc` (or extend existing blocs) to:
  - Fetch and manage historical heart rate data
  - Handle heart rate visualization state
  - Process heart rate insights and recommendations

## 5. Basic Analytics Features

Implement simple heart rate analytics features that don't require knowing the user's age:

### 5.1. Session-level Insights
- Calculate and display heart rate variability (standard deviation)
- Show heart rate trend during session (increasing, decreasing, or stable)
- Highlight periods of peak heart rate

## 6. Implementation Tasks

### 6.1. Immediate Implementation Tasks

#### A. Create Reusable Heart Rate Graph Component
- [ ] Create a new widget file: `heart_rate_graph.dart` in the widgets directory
- [ ] Implement a reusable `HeartRateGraph` widget that displays historical heart rate data
- [ ] Use the existing FL Chart package (already installed in pubspec.yaml)
- [ ] Add parameters for customization (height, tooltip options, etc.)
- [ ] Implement gradient fill and properly styled axes with time/BPM labels
- [ ] Ensure the graph properly displays the complete session timeline

#### B. Session Complete Screen Enhancement
- [ ] Update the stats grid to include heart rate tiles:
  - [ ] Add Avg HR tile with appropriate styling
  - [ ] Add Max HR tile with appropriate icon and color
- [ ] Position the heart rate graph between stats and ratings:
  - [ ] Ensure the graph only displays when heart rate data is available
  - [ ] Add appropriate section heading and spacing
- [ ] Test with various sample sizes and ensure good performance

#### C. Session Detail Screen Enhancement
- [ ] Restructure the header section layout:
  - [ ] Move the star rating display to the right of the date and time
  - [ ] Ensure proper alignment and spacing in the header
- [ ] Add heart rate section to the detail screen:
  - [ ] Create section header with "Heart Rate" title using consistent styling
  - [ ] Implement detail rows for Average HR and Maximum HR only
  - [ ] Add the heart rate graph below the stats with proper spacing
- [ ] Position the heart rate section immediately after the existing stats section
- [ ] Ensure proper scrolling behavior and responsiveness on different screen sizes

### 6.2. Future Enhancements
- Heart rate recovery analysis post-session
- Cardiovascular fitness trend analysis
- Integration with additional external HR sensors
- Export heart rate data to third-party analysis tools based on heart rate data

## 7. UX Considerations

### 7.1. User Settings
- Add heart rate preferences section in settings:
  - Max heart rate configuration
  - Heart rate zone customization
  - Display preferences (show/hide HR metrics)

### 7.2. Privacy Considerations
- Clearly explain heart rate data collection and usage
- Allow users to opt-out of heart rate tracking
- Ensure heart rate data is properly secured
- Consider privacy implications when sharing sessions with Ruck Buddies

## 8. Detailed Implementation Tasks

### I. Data Model & Backend
- [ ] **A. Heart Rate Sample Model Enhancements:**
  - [ ] Review existing `HeartRateSample` model
  - [ ] Add any missing fields for comprehensive tracking

- [ ] **B. Database Schema Updates:**
  - [ ] Update `heart_rate_samples` table with appropriate indices
  - [ ] Add heart rate summary fields to `ruck_session` table
  - [ ] Provide SQL to run directly in Supabase

- [ ] **C. API Endpoint Implementation:**
  - [ ] Create heart rate summary logic for existing heart rate samples
  - [ ] Implement database queries to calculate avg, max, min heart rates
  - [ ] Add summary data to session retrieval responses
  - [ ] Optimize queries for performance with large datasets

### II. Health Integration
- [ ] **A. iOS HealthKit:**
  - [ ] Review existing heart rate data collection
  - [ ] Optimize for battery efficiency
  - [ ] Implement background heart rate updates

- [ ] **B. Android Integration:**
  - [ ] Implement Google Fit heart rate data collection
  - [ ] Handle permissions and user opt-in
  - [ ] Implement background heart rate updates

### III. Frontend Implementation
- [ ] **A. Reusable Heart Rate Graph Component:**
  - [ ] Create `heart_rate_graph.dart` in the shared widgets directory
  - [ ] Implement visualization using FL Chart package
  - [ ] Add proper time and BPM axes with labels
  - [ ] Implement gradient styling and interactive tooltips

- [ ] **B. Session Complete Screen:**
  - [ ] Add Avg HR and Max HR tiles to the stats grid
  - [ ] Implement heart rate graph section below stats and above ratings
  - [ ] Add appropriate section heading and spacing
  - [ ] Ensure proper display only when heart rate data is available

- [ ] **C. Session Detail Screen:**
  - [ ] Move rating display to top right next to date and time
  - [ ] Add heart rate section after the detail stats section
  - [ ] Display Average HR and Maximum HR using existing styling
  - [ ] Implement heart rate graph below the stats
  - [ ] Ensure consistent styling with other detail screen components

## 9. Future Enhancements
- Heart rate variability (HRV) tracking for recovery analysis
- Training effect calculations based on heart rate data
- Smart workout recommendations based on heart rate trends
- Integration with additional external HR sensors
- Export heart rate data to third-party analysis tools
