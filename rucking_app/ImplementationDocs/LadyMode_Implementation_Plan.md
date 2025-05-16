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
- [x] **A. Database Changes:**
  - [x] Add `gender` field to `users` table in Supabase (options: 'male', 'female', 'other', 'prefer_not_to_say')
  - [x] Update user registration flow in backend to include gender field
  - [x] Create migration for existing users (default to null/unspecified)

- [x] **B. UI Implementation:**
  - [x] Add gender selection to signup/registration form
  - [x] Add gender selection to user profile/settings screen
  - [x] Create appropriate UI controls with inclusive options (Dropdown with Male, Female, Other, Prefer not to say)
  - [x] Add help text explaining how this information is used

### 4.2. Lady Rucker Visual Assets
- [x] **A. Splash Screen Update:**
  - [x] Create/acquire lady rucker splash screen graphic (already exists at `assets/images/go_ruck_yourself_lady.png`)
  - [x] Implement conditional logic in splash screen to show gender-appropriate graphic
  - [x] Add smooth transition for users who change gender setting
  - [x] Ensure asset quality matches existing graphics

- [x] **B. Map Pin Marker:**
  - [x] Create/acquire lady rucker map pin marker asset (already exists at `assets/images/map_marker_lady.png`)
  - [x] Modify map implementation to use gender-appropriate marker via `_buildGenderSpecificMarker()`
  - [x] Test marker visibility and clarity at different zoom levels
  - [x] Ensure consistent styling with other app graphics

- [x] **C. Navigation & Profile Icons:**
  - [x] Update profile icon in bottom navigation bar to be gender-specific
  - [x] Implement `_buildProfileIcon()` method to check user gender and display appropriate icon
  - [x] Use new assets: `lady rucker profile.png` and `lady rucker profile active.png`
  - [x] Add fallback for users with unspecified gender
  - [x] Test display across different screen sizes and device densities

### 4.3. Gender-Based Calculations
- [x] **A. Calorie Calculation Updates:**
  - [x] Research scientifically validated gender differences in calorie expenditure during rucking
  - [x] Update calorie calculation algorithm to incorporate gender factor (15% reduction for females)
  - [x] Document adjustment factors with references in code comments
  - [ ] Create unit tests to verify calculations

- [x] **B. Integration Points:**
  - [x] Identify all places in code where calorie calculations occur (`MetCalculator` class)
  - [x] Modify each calculation to check user gender (`calculateRuckingCalories` method)
  - [x] Add appropriate adjustments based on gender (multipliers for different genders)
  - [x] Ensure real-time calorie display updates correctly in active session

- [ ] **C. Testing:**
  - [x] Verify calorie calculations match expected values for both genders
  - [ ] Test edge cases (gender changes mid-session, etc.)
  - [ ] Perform integration testing in real-world scenarios

## 5. Technical Implementation Details

### 5.1. Gender-Specific Calorie Formula (Implemented)

```dart
// Actual implementation in MetCalculator.calculateRuckingCalories
double calculateRuckingCalories({
  required double userWeightKg,
  required double ruckWeightKg,
  required double distanceKm,
  required int elapsedSeconds,
  double elevationGain = 0.0,
  double elevationLoss = 0.0,
  String? gender,
}) {
  // ...calculate base calories using MET formula...
  
  // Apply gender-based adjustment
  double genderAdjustedCalories = baseCalories;
  if (gender == 'female') {
    // Female adjustment: 15% lower calorie burn due to body composition differences
    genderAdjustedCalories = baseCalories * 0.85;
  } else if (gender == 'male') {
    // Male baseline - no adjustment needed
    genderAdjustedCalories = baseCalories;
  } else {
    // If gender is not specified, use a middle ground (7.5% reduction)
    genderAdjustedCalories = baseCalories * 0.925;
  }
  
  return genderAdjustedCalories;
}
```

### 5.2. Visual Asset Switching Logic (Implemented)

```dart
// Implemented in SplashScreen.build
String splashImagePath = (userGender == 'female')
    ? 'assets/images/go_ruck_yourself_lady.png' // Female version
    : 'assets/images/go ruck yourself.png'; // Default/male version

// Implemented in _RouteMapState._buildGenderSpecificMarker
Widget _buildGenderSpecificMarker() {
  // Get user gender from AuthBloc
  String? userGender;
  try {
    final authBloc = GetIt.instance<AuthBloc>();
    if (authBloc.state is Authenticated) {
      userGender = (authBloc.state as Authenticated).user.gender;
    }
  } catch (e) {
    debugPrint('Could not get user gender for map marker: $e');
  }
  
  // Determine which marker image to use based on gender
  final String markerImagePath = (userGender == 'female')
      ? 'assets/images/map_marker_lady.png' // Female version
      : 'assets/images/map marker.png'; // Default/male version
  
  return Image.asset(markerImagePath);
}
```

## 6. Testing Requirements

- [ ] Unit test gender-based calorie calculations
- [x] Verify visual assets load correctly based on gender
- [x] Test gender selection UI in profile settings
- [x] End-to-end testing of gender selection to visual appearance
- [x] Verify calorie calculations are appropriate for different genders

## 7. Future Enhancements

- Implement gender-specific workout recommendations
- Add gender-specific recovery time suggestions
- Consider menstrual cycle tracking integration for female users to optimize workouts
- Enhance analytics to track performance metrics by gender for more personalized insights

---

This implementation plan provides a focused approach to enhancing the Rucking App with gender-specific features that improve both accuracy and inclusivity for female users.
