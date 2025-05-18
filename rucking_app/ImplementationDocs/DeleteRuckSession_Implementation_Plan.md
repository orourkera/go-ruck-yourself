# Delete Ruck Session - Implementation Plan

## 1. Overview & Goal

Allow users to permanently delete a specific ruck session and all its associated data (location points, heart rate samples) from the application. Deletion should be accessible from the Session Detail Screen and the screen shown immediately after completing a ruck (referred to as the "Session Complete" context).

## 2. Frontend Implementation

### 2.1. Session Detail Screen (`session_detail_screen.dart`)
- Add a "Delete this ruck" text link.
  - Style: Subtle, red color (e.g., `Colors.red`).
  - Placement: Centered at the bottom of the page/scrollable content.
- On tap: Trigger the confirmation dialog.

### 2.2. "Session Complete" Context (Post-Session Review)
- This will be implemented on the `session_complete_screen.dart`.
- Add a "Discard this ruck" text link.
  - Style: Subtle, red color.
  - Placement: Centered at the bottom of the page/scrollable content.
- On tap: Trigger the confirmation dialog.

### 2.3. Confirmation Dialog
- **Widget:** Use `AlertDialog` or a custom dialog.
- **Title:** Text: "Delete Ruck?" (or "Discard Ruck?").
- **Content:** Text: "This will delete this ruck session and all associated data including heart rate and location points. This action cannot be undone."
- **Actions (Buttons):**
    - `TextButton` with text "Cancel". On pressed: `Navigator.of(context).pop()`. 
    - `TextButton` with text "Delete" (or "Discard"). 
        - Style: Text in red color.
        - On pressed: `Navigator.of(context).pop(true)` (or call BLoC event directly and then pop).

### 2.4. State Management & Action Flow
- The BLoC managing session details (e.g., `SessionDetailBloc`, or one dedicated to session actions) will handle this.
- **Events:**
    - `DeleteSessionRequested(String sessionId)`
- **States (relevant to deletion):**
    - `SessionActionInProgress` (generic state for actions like delete/save)
    - `SessionDeleteSuccess`
    - `SessionActionFailure(String error)`
- **Workflow:**
    1. User taps "Delete"/"Discard" link.
    2. Confirmation dialog shown.
    3. User confirms deletion.
    4. BLoC event `DeleteSessionRequested` is added.
    5. BLoC transitions to `SessionActionInProgress` (or similar loading state).
    6. BLoC calls a repository/service method to execute the API request.
    7. On API success:
        - BLoC transitions to `SessionDeleteSuccess`.
        - UI shows a success message (e.g., `SnackBar`: "The session is gone, rucker. Gone forever.").
        - UI navigates to the homepage (e.g., `Navigator.of(context).pushNamedAndRemoveUntil('/home', (Route<dynamic> route) => false)`).
        - Any parent list/view should refresh to reflect the deletion (though navigating to home might make this less direct an issue for the immediate previous screen).
    8. On API failure:
        - BLoC transitions to `SessionActionFailure` with the error message.
        - UI shows an error message (e.g., `SnackBar`: "Failed to delete ruck: [error]").

## 3. Backend Implementation

### 3.1. New API Endpoint
- **Route:** `DELETE /rest/v1/ruck_session?id=eq.{session_id}` (This is a Supabase-conventional way if RLS handles authorization and cascade. If a custom function is needed for atomicity or complex logic, it might be `POST /rpc/delete_ruck_session` with `session_id` in the body).
- **Authentication:** Handled by Supabase (user must be authenticated).
- **Authorization:** Row Level Security (RLS) policy on `ruck_session` table must ensure that only the user who owns the session (e.g., `auth.uid() == user_id`) can delete it.

### 3.2. Deletion Logic
- **Primary Concern: Atomicity and Data Integrity.**
- **Option 1: Rely on `ON DELETE CASCADE` (Preferred & Simplest if set up):**
    - Verify that Foreign Key constraints from `heart_rate_samples.session_id` to `ruck_session.id` AND `location_point.session_id` to `ruck_session.id` are configured with `ON DELETE CASCADE` in the Supabase database schema.
    - If so, the RLS-protected `DELETE` operation on the `ruck_session` table is sufficient. Supabase will handle deleting associated child records automatically and atomically.
- **Option 2: Custom Database Function (if `ON DELETE CASCADE` is not feasible or additional logic is needed):**
    - Create a PostgreSQL function (e.g., `delete_user_ruck_session(session_id_to_delete UUID)`).
    - This function would:
        1. Verify ownership: `SELECT user_id FROM ruck_session WHERE id = session_id_to_delete` and check if it matches `auth.uid()`.
        2. Delete from `heart_rate_samples` WHERE `session_id = session_id_to_delete`.
        3. Delete from `location_point` WHERE `session_id = session_id_to_delete`.
        4. Delete from `ruck_session` WHERE `id = session_id_to_delete`.
        5. The operations inside the function are transactional by default.
    - Expose this function via Supabase API (e.g., `POST /rpc/delete_user_ruck_session`).
- **Option 3: Backend Code in a Serverless Function/Custom Server (More complex for this setup):**
    - If using a separate backend layer beyond Supabase's direct API (e.g., custom Flask/Node.js endpoints that then talk to Supabase with service key).
    - This layer would perform the ownership check and the three delete operations, ideally within a transaction managed by the Supabase client library.

### 3.3. API Response (for Supabase direct DELETE or RPC)
- **Success:** HTTP 204 No Content (if direct `DELETE`), or HTTP 200 OK (if RPC function returns successfully, possibly with a minimal JSON response or nothing).
- **Failure (handled by Supabase RLS/PostgREST):**
    - HTTP 401 Unauthorized (if user not authenticated).
    - HTTP 403 Forbidden (if RLS policy prevents deletion - e.g., not the owner).
    - HTTP 404 Not Found (if `session_id` does not exist, or RLS makes it appear so).
    - HTTP 5xx for server-side issues.

## 4. Database Considerations

### 4.1. Foreign Key Constraints & `ON DELETE CASCADE`
- **Task:** Log in to Supabase dashboard.
- **Task:** Navigate to Database -> Tables. Select `heart_rate_samples` and `location_point`.
- **Task:** Check constraints on `session_id` column for each. Verify it's a Foreign Key to `ruck_session(id)` and see if `ON DELETE CASCADE` is specified.
- **Decision:** If not present, decide whether to add `ON DELETE CASCADE` (recommended for simplicity) or handle deletion via a custom PL/pgSQL function (see 3.2 Option 2).

### 4.2. RLS (Row Level Security) Policies
- **`ruck_session` table:**
    - **Task:** Verify/ensure a `DELETE` policy exists. Example:
      ```sql
      CREATE POLICY "Users can delete their own ruck sessions" 
      ON ruck_session FOR DELETE 
      USING (auth.uid() = user_id);
      ```
- **`heart_rate_samples` & `location_point` tables:**
    - If `ON DELETE CASCADE` is used, RLS delete policies on these tables are less critical for *this specific delete flow initiated from `ruck_session`*, as the cascade bypasses RLS checks on child tables *for cascaded deletes*.
    - If manual deletion via a custom PL/pgSQL function run by the user (`SECURITY DEFINER` not used or used carefully), then appropriate `DELETE` policies would be needed on these tables as well, or the function needs `SECURITY DEFINER` to run with elevated privileges (typically the role that created the function).

## 5. User Experience (Summary)
- Clear visual cues for destructive action (red links/buttons).
- Explicit confirmation dialog with a strong warning.
- Feedback to the user on success or failure of the deletion.
- Smooth navigation and data refresh post-deletion.

## 6. Detailed Task Checklist

### I. Database Setup & Verification (Supabase)
- [ ] **A. Verify `heart_rate_samples` Table:**
    - [ ] Check Foreign Key from `heart_rate_samples.session_id` to `ruck_session.id`.
    - [ ] Confirm if `ON DELETE CASCADE` is enabled for this FK.
    - [ ] If not, decide: Add `ON DELETE CASCADE` or plan for manual deletion in backend logic.
- [ ] **B. Verify `location_point` Table:**
    - [ ] Check Foreign Key from `location_point.session_id` to `ruck_session.id`.
    - [ ] Confirm if `ON DELETE CASCADE` is enabled for this FK.
    - [ ] If not, decide: Add `ON DELETE CASCADE` or plan for manual deletion in backend logic.
- [ ] **C. `ruck_session` Table RLS Policy:**
    - [ ] Review/Create RLS policy for `DELETE` operations, ensuring users can only delete their own sessions (`auth.uid() = user_id`).
- [ ] **D. (If not using CASCADE) `heart_rate_samples` & `location_point` RLS Policies:**
    - [ ] If manual deletion is performed and not using a `SECURITY DEFINER` function, ensure RLS `DELETE` policies allow deletion based on `ruck_session` ownership.

### II. Backend API Development (Supabase / Custom Function)
- [ ] **A. Choose Deletion Strategy:**
    - [ ] Strategy 1: Direct Supabase `DELETE` on `ruck_session` (if `ON DELETE CASCADE` is fully enabled for child tables).
    - [ ] Strategy 2: Create/Use a PL/pgSQL function (e.g., `delete_user_ruck_session`) to handle multi-table deletes atomically and perform ownership checks.
- [ ] **B. Implement Deletion Endpoint/Logic:**
    - [ ] **If Strategy 1:** Ensure RLS on `ruck_session` is sufficient. Frontend will call `DELETE /rest/v1/ruck_session?id=eq.{session_id}`.
    - [ ] **If Strategy 2:**
        - [ ] Write and test the PL/pgSQL function (`delete_user_ruck_session(session_id_to_delete UUID)`).
            - Include ownership check (`auth.uid()`).
            - Include deletes for `heart_rate_samples`, `location_point`, then `ruck_session`.
        - [ ] Expose the function via Supabase RPC (e.g., `POST /rpc/delete_user_ruck_session`).
        - [ ] Ensure appropriate RLS or function security settings (`SECURITY INVOKER` or `SECURITY DEFINER` with caution).

### III. Frontend Implementation (Flutter)
- **A. UI Elements:**
    - [ ] **`session_detail_screen.dart`:**
        - [ ] Add "Delete this ruck" text link (styled red, centered at bottom of page).
        - [ ] Implement tap handler to show confirmation dialog.
    - [ ] **`session_complete_screen.dart` (Session Complete Context):**
        - [ ] Add "Discard this ruck" text link (styled red, centered at bottom of page).
        - [ ] Implement tap handler to show confirmation dialog.
    - [ ] **Confirmation Dialog Widget:**
        - [ ] Create reusable `AlertDialog` (or custom).
        - [ ] Include title, warning message ("This will delete this ruck session and all associated data including heart rate and location points. This action cannot be undone.").
        - [ ] Implement "Cancel" button.
        - [ ] Implement "Delete"/"Discard" button (styled red text).
- **B. State Management (BLoC/Cubit for Session Details/Actions):**
    - [ ] Define `DeleteSessionRequested(String sessionId)` event.
    - [ ] Define states: `SessionActionInProgress`, `SessionDeleteSuccess`, `SessionActionFailure(String error)`
    - [ ] Implement BLoC logic:
        - On `DeleteSessionRequested`, transition to `SessionActionInProgress`.
        - Call repository/service method for backend API.
        - On success, transition to `SessionDeleteSuccess`, trigger success feedback (SnackBar: "The session is gone, rucker. Gone forever.") and navigation to homepage.
        - On failure, transition to `SessionActionFailure`, trigger error feedback (SnackBar).
- **C. Repository/Service Layer:**
    - [ ] Add method to call the backend delete endpoint (e.g., `Future<void> deleteRuckSession(String sessionId)`).
    - [ ] Handle API responses and potential errors.
- **D. Navigation & Data Refresh:**
    - [ ] On successful deletion, navigate user to the homepage.
    - [ ] Display SnackBar with message: "The session is gone, rucker. Gone forever."
    - [ ] Ensure any relevant data sources or BLoCs that populate the homepage (or other lists) are refreshed if they cache session data.

### IV. Testing
- [ ] **A. Backend Testing:**
    - [ ] **If PL/pgSQL function:** Unit test the function directly in Supabase SQL editor or via API call. Test ownership, cascade (if applicable), and atomicity.
    - [ ] Test RLS policies for `DELETE` on `ruck_session`.
    - [ ] Test API endpoint with valid and invalid session IDs, and for sessions owned by other users (should fail).
- [ ] **B. Frontend BLoC/Cubit Tests:**
    - [ ] Test state transitions for delete operation (request, success, failure).
    - [ ] Mock repository calls.
- [ ] **C. Frontend Widget Tests:**
    - [ ] Test display of "Delete"/"Discard" links.
    - [ ] Test confirmation dialog appearance and button actions.
- [ ] **D. Integration Tests (Frontend-Backend):**
    - [ ] Test the full flow: tap link -> confirm dialog -> BLoC action -> API call -> UI update.
- [ ] **E. Manual End-to-End Testing:**
    - [ ] Delete a session from `session_detail_screen.dart`.
    - [ ] Delete a session from the "Session Complete" context.
    - [ ] Verify data is removed from `ruck_session`, `location_point`, and `heart_rate_samples` tables in Supabase.
    - [ ] Verify UI updates correctly (navigation, list refresh).
    - [ ] Test error scenarios (e.g., network error during deletion).
