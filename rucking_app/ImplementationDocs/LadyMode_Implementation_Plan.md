# Lady Mode - Implementation Plan

## 1. Overview & Goal

Add a "Lady Mode" feature to the Rucking App to better serve female users by providing gender-appropriate visuals and more accurate calorie calculations. This feature will make the app more inclusive and effective for female users by recognizing biological differences that influence rucking performance.

## 2. Features & Considerations

### 2.1. Physiological Considerations
- **Calorie Calculations**: Use female-specific BMR formulas for more accurate calorie expenditure tracking
- **Recovery Recommendations**: Adapt recovery time suggestions to account for potential hormonal fluctuations during menstrual cycles

### 2.2. UX/UI Elements
- **Setting Toggle**: Add a "Lady Mode" option in user settings with a clear explanation of its purpose and effects

## 3. Implementation Overview

The implementation will focus on three core components:

1. **Gender Selection**: Allow users to specify their gender in their profile
2. **Visual Assets**: Update splash screen and map markers based on gender
3. **Calorie Calculations**: Adjust calorie calculations based on biological differences

## 4. Priority Implementation Items

### 4.1. Gender Selection in User Profile
- [ ] **A. Database Changes:**
  - [ ] Add `gender` field to `users` table in Supabase (options: 'male', 'female', 'other', 'prefer_not_to_say')
  - [ ] Update user registration flow in backend to include gender field
  - [ ] Create migration for existing users (default to null/unspecified)

- [ ] **B. UI Implementation:**
  - [ ] Add gender selection to signup/registration form
  - [ ] Add gender selection to user profile/settings screen
  - [ ] Create appropriate UI controls with inclusive options
  - [ ] Add help text explaining how this information is used

### 4.2. Lady Rucker Visual Assets
- [ ] **A. Splash Screen Update:**
  - [x] Create/acquire lady rucker splash screen graphic (already exists at `assets/images/lady rucker.png`)
  - [ ] Implement conditional logic in splash screen to show gender-appropriate graphic
  - [ ] Add smooth transition for users who change gender setting
  - [ ] Ensure asset quality matches existing graphics

- [ ] **B. Map Pin Marker:**
  - [x] Create/acquire lady rucker map pin marker asset (already exists at `assets/images/lady rucker.png`)
  - [ ] Modify map implementation to use gender-appropriate marker
  - [ ] Test marker visibility and clarity at different zoom levels
  - [ ] Ensure consistent styling with other app graphics

- [ ] **C. Ruck Buddies Avatars:**
  - [ ] Replace generic circle avatars in Ruck Buddies screen with gender-specific rucker icons
  - [ ] Modify `RuckBuddyCard._buildAvatar()` to check user gender and display appropriate icon
  - [ ] Ensure the API returns gender information with ruck buddy data
  - [ ] Add fallback for users with unspecified gender
  - [ ] Test display across different screen sizes and device densities

### 4.3. Gender-Based Calculations
- [ ] **A. Calorie Calculation Updates:**
  - [ ] Research scientifically validated gender differences in calorie expenditure during rucking
  - [ ] Update calorie calculation algorithm to incorporate gender factor
  - [ ] Document adjustment factors with scientific references
  - [ ] Create unit tests to verify calculations

- [ ] **B. Integration Points:**
  - [ ] Identify all places in code where calorie calculations occur
  - [ ] Modify each calculation to check user gender
  - [ ] Add appropriate adjustments based on gender
  - [ ] Ensure real-time calorie display updates correctly

- [ ] **C. Testing:**
  - [ ] Verify calorie calculations match expected values for both genders
  - [ ] Test edge cases (gender changes mid-session, etc.)
  - [ ] Perform integration testing in real-world scenarios

## 5. Technical Implementation Details

### 5.1. Gender-Specific Calorie Formula

```dart
// Example adjustment:
double calculateCalories(double weightKg, int durationMinutes, double intensityFactor, String? gender) {
  // Female users burn approximately 15-20% fewer calories than males for the same activity
  double genderFactor = (gender?.toLowerCase() == 'female') ? 0.85 : 1.0;
  return weightKg * durationMinutes * intensityFactor * genderFactor;
}
```

### 5.2. Visual Asset Switching Logic

```dart
// Example conditional asset loading
String getAssetPath(String assetName, String? gender) {
  if (gender?.toLowerCase() == 'female') {
    return 'assets/images/lady_$assetName.png';
  } else {
    return 'assets/images/$assetName.png';
  }
}
```

## 6. Testing Requirements

- [ ] Unit test gender-based calorie calculations
- [ ] Verify visual assets load correctly based on gender
- [ ] Test gender selection UI in profile settings
- [ ] End-to-end testing of gender selection to visual appearance
- [ ] Verify calorie calculations are appropriate for different genders

---

This implementation plan provides a focused approach to enhancing the Rucking App with gender-specific features that improve both accuracy and inclusivity for female users.
