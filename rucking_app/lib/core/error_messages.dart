/// Error messages for the Rucking App
/// These can be customized as needed for different parts of the application.

// Authentication Error Messages
const String authInvalidCredentials = 'Invalid email or password, rucker. Please try again.';
const String authUserNotFound = 'No account found with this email, rucker. Please sign up.';
const String authEmailInUse = 'An account with this email already exists, rucker. Please log in.';
const String authWeakPassword = 'Password is too weak, rucker. Please use a stronger password.';
const String authGenericError = 'An error occurred during authentication, rucker. Please try again.';
const String authNetworkError = 'Network error. Please check your internet connection and try again.';

// Server Error Messages
const String serverConnectionError = 'Unable to connect to the server, rucker. Please check your internet connection.';
const String serverTimeoutError = 'Server request timed out. Please try again later.';
const String serverInternalError = 'An internal server error occurred. Please try again later.';
const String serverUnauthorized = 'You are not authorized to perform this action. Please log in again.';
const String serverNotFound = 'Requested resource not found on the server.';
const String serverGenericError = 'An unexpected server error occurred. Please try again.';

// Session Error Messages (Active Session Screen)
const String sessionUserWeightRequired = 'User weight is required, rucker. We need it to accurately count calories.';
const String sessionInvalidWeight = 'Please enter a valid weight greater than 0, rucker.';
const String sessionInvalidDuration = 'Please enter a valid duration greater than 0, rucker.';
const String sessionLocationPermissionDenied = 'Location permission denied, rucker. Please enable location services to track your ruck session.';
const String sessionLocationServiceDisabled = 'Location services are disabled, rucker. Please enable location services to start tracking.';
const String sessionStartError = 'Failed to start the session, rucker. Please try again.';
const String sessionUpdateError = 'Failed to update session data, rucker. Data may not be saved correctly.';
const String sessionEndError = 'Failed to end the session, rucker. Please try again.';
const String sessionIdleTimeout = 'Session ended due to inactivity, rucker. You stood around for too long.';
const String sessionValidationError = 'Session data is invalid, rucker. Please check your inputs and try again.';
const String sessionTooShortError = 'Not long enough, rucker. Minimum duration is {minutes} minutes.';
const String sessionDistanceTooShortError = 'Distance too short, rucker. Minimum distance is 100 meters.';
const String sessionCaloriesTooLowError = 'Not enough calories burned to save this session, rucker. Move more!';
const String sessionGenericError = 'An error occurred during the session, rucker. Please try again.';
const String sessionAutoPaused = 'Auto-paused, rucker. No movement detected for 1+ minute. Get moving!';

// RevenueCat Service Error Messages
const String revenueCatApiKeyMissing = 'RevenueCat API Key is missing. Please configure your .env file with REVENUECAT_API_KEY.';
const String revenueCatPurchaseError = 'Failed to complete purchase, rucker. Please try again later.';
const String revenueCatSubscriptionStatusError = 'Unable to check subscription status, rucker. Please try again.';
const String revenueCatRestorePurchasesError = 'Failed to restore purchases, rucker. Please try again.';
