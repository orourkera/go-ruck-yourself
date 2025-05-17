# Ruck Buddies 2.0 - Implementation Plan

## 1. Overview & Goal

The "Ruck Buddies 2.0" update aims to enhance the social features of the Rucking App, creating a more engaging and interactive community experience. Key enhancements include photo sharing capabilities, a dedicated ruck buddies detail view, interactive social features (likes and comments), and a notification system to keep users engaged with community interactions.

## 2. Core Features

### 2.1. Photo Sharing
- **Upload photos**: Allow users to attach photos to their ruck sessions
- **Photo management**: Enable users to view and delete photos they've uploaded
- **Photo display**: Show photos in an attractive carousel in both personal and community views

### 2.2. Ruck Buddies Detail View
- Create a dedicated view for each community ruck that matches the layout of the session detail screen
- Add social interaction capabilities specific to the community context

### 2.3. Social Interactions
- **Likes**: Allow users to "like" other users' rucks
- **Comments**: Enable users to leave comments on other users' rucks
- **Activity tracking**: Record all social interactions for notification purposes

### 2.4. Notifications
- Implement a notification system to alert users when someone interacts with their content
- Display a notification bell on the homepage with unread count indicator

## 3. Frontend Implementation

### 3.1. Photo Management

#### 3.1.1. Session Complete Screen (`session_complete_screen.dart`)
- Add a photo upload section after the session stats
- **Photo upload component**:
  - Button to trigger device camera or photo library access
  - Preview of selected photos before submission
  - Progress indicator for upload process
  - Limit of 5 photos per session

#### 3.1.2. Session Detail Screen (`session_detail_screen.dart`)
- Add a new section to display existing photos in a carousel
- **Photo management**:
  - Add ability to upload additional photos
  - Add ability to delete existing photos with confirmation dialog
  - Add ability to view photos in full-screen mode

#### 3.1.3. Shared Photo Components
- Create reusable widgets:
  - `PhotoCarousel`: Horizontally scrollable container for displaying photos
  - `PhotoUploadButton`: Consistent UI for triggering photo selection
  - `PhotoViewer`: Full-screen photo viewer with pinch-to-zoom and swipe navigation

### 3.2. Ruck Buddies Feed Enhancements

#### 3.2.1. Ruck Buddies Screen (`ruck_buddies_screen.dart`)
- Update the existing ruck card to:
  - ✅ Display a photo thumbnail if photos are available
  - ✅ Indicate the likes and comments count
  - ✅ Add tap action to navigate to the new detail view
  - ✅ Removed photo count icon from bottom right (redundant with thumbnail display)

#### 3.2.2. Ruck Card Widget (`ruck_buddy_card.dart`)
- Enhance the existing card design:
  - ✅ Add a photo thumbnail overlay or carousel preview
  - ✅ Add social metrics (likes count, comments count)
  - ✅ Continue using the existing man/lady rucker profile images based on user gender
  - ✅ Improve visual hierarchy to highlight user-generated content

### 3.3. Ruck Buddies Detail Screen (`ruck_buddy_detail_screen.dart`)
- ✅ Create a new screen modeled after the session detail screen that includes:
  - ✅ All session stats matching the session detail layout
  - ✅ Photo carousel section if photos are available
  - ✅ New social interaction section:
    - ✅ Like button with animation
    - ✅ Comments section with:
      - ✅ Text input for adding new comments
      - ✅ List of existing comments with user attribution
      - ✅ Timestamp for each comment
      - ✅ Delete option for user's own comments

### 3.4. Notification System

#### 3.4.1. Notification Bell (`notification_bell.dart`)
- Create a widget for the notification bell:
  - Bell icon with unread count indicator
  - Animation for new notifications
  - Tap action to navigate to notification screen

#### 3.4.2. Notification Screen (`notifications_screen.dart`)
- Implement a screen to display all notifications:
  - List of notifications sorted by date (newest first)
  - Different visual styling for read/unread notifications
  - Action buttons to:
    - Mark all as read
    - Navigate to the related content
  - Pull-to-refresh functionality

#### 3.4.3. Notification Card (`notification_card.dart`)
- Create a reusable card for displaying individual notifications:
  - User identifier with man/lady rucker profile image based on user gender (no custom avatars)
  - Action type (like, comment)
  - Preview of content (comment text, photo thumbnail)
  - Timestamp
  - Read/unread status indicator

### 3.5. Navigation Updates
- Add notification bell to the app bar on the home screen
- Update routing to include the new screens:
  - `/notifications` route for the notifications screen
  - `/ruck_buddies/:id` route for the ruck buddy detail screen

### 3.6. State Management

#### 3.6.1. Photo Management
- Enhance `SessionBloc` to handle photo operations:
  - Add events: `UploadPhotosRequested`, `DeletePhotoRequested`
  - Add states: `PhotosUploading`, `PhotosUploadSuccess`, `PhotosUploadFailure`
  - Track photo upload progress

#### 3.6.2. Social Interactions
- Create `SocialBloc` to manage likes and comments:
  - Add events: `LikeToggled`, `CommentAdded`, `CommentDeleted`
  - Add states to track interaction status
  - Handle optimistic updates for better UX

#### 3.6.3. Notifications
- Create `NotificationBloc` to manage notification state:
  - Add events: `NotificationsRequested`, `NotificationRead`, `AllNotificationsRead`
  - Add states: `NotificationsLoading`, `NotificationsLoaded`, `NotificationsError`
  - Handle background polling for new notifications

## 4. Backend Implementation

### 4.1. Database Schema Updates

#### 4.1.1. Ruck Sessions Table
- Add a relationship to photos:
  ```
  ALTER TABLE ruck_sessions
  ADD COLUMN has_photos BOOLEAN DEFAULT FALSE;
  ```

#### 4.1.2. Photos Table
- Create a new table for storing photo metadata:
  ```
  CREATE TABLE ruck_photos (
    id SERIAL PRIMARY KEY,
    ruck_id INTEGER REFERENCES ruck_sessions(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id),
    filename TEXT NOT NULL,
    original_filename TEXT,
    content_type TEXT,
    size INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(ruck_id, filename)
  );
  ```

#### 4.1.3. Social Interactions Tables
- Create tables for likes and comments:
  ```
  CREATE TABLE ruck_likes (
    id SERIAL PRIMARY KEY,
    ruck_id INTEGER REFERENCES ruck_sessions(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(ruck_id, user_id)
  );

  CREATE TABLE ruck_comments (
    id SERIAL PRIMARY KEY,
    ruck_id INTEGER REFERENCES ruck_sessions(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id),
    comment TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
  ```

#### 4.1.4. Notifications Table
- Create a table for storing notifications:
  ```
  CREATE TABLE notifications (
    id SERIAL PRIMARY KEY,
    recipient_id INTEGER REFERENCES users(id),
    sender_id INTEGER REFERENCES users(id),
    ruck_id INTEGER REFERENCES ruck_sessions(id) ON DELETE CASCADE,
    comment_id INTEGER REFERENCES ruck_comments(id) ON DELETE CASCADE,
    type TEXT CHECK (type IN ('like', 'comment')),
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
  ```

### 4.2. API Endpoints

#### 4.2.1. Photo Management Endpoints
- **Upload Photos**: `POST /api/rucks/:id/photos`
  - Request: `multipart/form-data` with photo files
  - Response: Array of photo metadata
  
- **Get Photos**: `GET /api/rucks/:id/photos`
  - Response: Array of photo metadata with URLs
  
- **Delete Photo**: `DELETE /api/rucks/:id/photos/:photo_id`
  - Response: Success message

#### 4.2.2. Social Interaction Endpoints
- **Toggle Like**: `POST /api/rucks/:id/like`
  - Response: Updated like count and status
  
- **Get Likes**: `GET /api/rucks/:id/likes`
  - Response: Array of users who liked the ruck
  
- **Add Comment**: `POST /api/rucks/:id/comments`
  - Request: `{ comment: "Text content" }`
  - Response: Newly created comment object
  
- **Get Comments**: `GET /api/rucks/:id/comments`
  - Response: Array of comments with user details
  
- **Delete Comment**: `DELETE /api/rucks/:id/comments/:comment_id`
  - Response: Success message

#### 4.2.3. Notification Endpoints
- **Get Notifications**: `GET /api/notifications`
  - Query parameters:
    - `unread_only`: boolean
    - `limit`: integer
    - `offset`: integer
  - Response: Array of notification objects
  
- **Mark Notification Read**: `PUT /api/notifications/:id/read`
  - Response: Updated notification object
  
- **Mark All Notifications Read**: `PUT /api/notifications/read_all`
  - Response: Success message
  
- **Get Unread Count**: `GET /api/notifications/unread_count`
  - Response: `{ count: number }`

### 4.3. Supabase Storage Integration

#### 4.3.1. Storage Configuration
- Create a dedicated storage bucket in Supabase for ruck photos:
  ```sql
  -- Create a bucket for ruck photos with public read access
  INSERT INTO storage.buckets (id, name, public) 
  VALUES ('ruck-photos', 'Ruck Photos', true);
  ```

- Set up storage structure:
  ```
  storage/
    ├── ruck-photos/
    │   ├── [user_id]/
    │   │   ├── [ruck_id]/
    │   │   │   ├── original/
    │   │   │   │   ├── [photo_id].jpg
    │   │   │   ├── thumbnails/
    │   │   │   │   ├── [photo_id].jpg
  ```

#### 4.3.2. Security Policies
- Implement Row-Level Security (RLS) policies:
  ```sql
  -- Allow all authenticated users to view any ruck photo
  CREATE POLICY "Users can view any ruck photo"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'ruck-photos');
  
  -- Allow users to upload their own photos only
  CREATE POLICY "Users can upload their own photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'ruck-photos' AND
    auth.uid()::text = (storage.foldername(name))[1]
  );
  
  -- Allow users to delete only their own photos
  CREATE POLICY "Users can delete their own photos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'ruck-photos' AND
    auth.uid()::text = (storage.foldername(name))[1]
  );
  ```

#### 4.3.3. Photo Upload Process
1. Generate a unique photo ID (UUID)
2. Create the proper storage path: `user_id/ruck_id/original/photo_id.extension`
3. Upload the file to Supabase storage
4. Generate a thumbnail using Supabase's transformation parameters
5. Store the photo metadata in the database
6. Return the complete RuckPhoto object with public URLs

#### 4.3.4. URL Construction
- Construct public URLs for images using Supabase's pattern:
  ```dart
  final publicUrl = '${supabaseUrl}/storage/v1/object/public/$bucketName/$path';
  ```
- For thumbnails, add transformation parameters:
  ```dart
  final thumbnailUrl = '$publicUrl?width=200&height=200&resize=contain';
  ```

### 4.4. Real-time Updates (Optional Enhancement)
- Implement WebSocket connections for real-time notifications:
  - `socket.io` or similar technology
  - Emit events when new likes or comments are received
  - Update notification count in real-time

## 5. Security Considerations

### 5.1. Photo Upload Security
- Implement file type validation to prevent malicious uploads
- Set reasonable file size limits (5MB per photo recommended)
- Generate random filenames to prevent path traversal attacks
- Scan uploaded content for malware (if feasible)

### 5.2. Privacy Controls
- Ensure photos are only accessible to authorized users
- Add user setting to control whether their photos are visible to others
- Include appropriate terms of service for user-generated content

### 5.3. Content Moderation
- Define a process for users to report inappropriate content
- Consider implementing automated content moderation for photos
- Create admin tools to review and remove reported content

## 6. Performance Considerations

### 6.1. Optimizing Photo Loading
- Use thumbnails in list views to reduce bandwidth
- Implement lazy loading for photos in carousels
- Cache photos locally after first load

### 6.2. Efficient Notifications
- Batch notification processing on the server
- Use pagination for notification lists
- Consider polling versus push mechanisms based on user activity

## 8. Implementation Phases

## 9. Implementation Progress

### Completed Tasks
- ✅ Connected Ruck Buddies feature to backend API endpoint (`/api/ruck-buddies`)
- ✅ Updated data models and repository to handle proper filtering (closest, calories, distance, duration, elevation)
- ✅ Added location support for the "closest" filter option
- ✅ Improved UI by removing redundant photo count display
- ✅ Enhanced the ruck buddy card with photo thumbnails and social metrics
- ✅ Implemented detail view navigation on card tap

### Phase 1: Photo Management
- ⬜ Implement photo upload on session complete screen
- ⬜ Add photo display and management to session detail screen
- ⬜ Create backend endpoints and storage for photos

### Phase 2: Ruck Buddies Detail View
- ✅ Create the detailed view for community rucks
- ✅ Update ruck buddies feed to link to detail view
- ✅ Include photo display in feed and detail views

### Phase 3: Social Interactions
- ⬜ Implement like functionality (UI in place, backend integration needed)
- ⬜ Develop comment system
- ⬜ Create backend support for social interactions

### Phase 4: Notifications
- ⬜ Implement notification data structure and API
- ⬜ Create notification UI (bell icon, notification screen)
- ⬜ Integrate notification system with social features
