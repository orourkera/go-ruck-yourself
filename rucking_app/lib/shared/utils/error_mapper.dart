// Shared error message mapper for user-friendly errors
String mapFriendlyErrorMessage(String? error) {
  if (error == null) return 'An unexpected error occurred.';
  final e = error.toLowerCase();

  if (e.contains('500')) return 'What the ruck, please try again later.';
  if (e.contains('401') || e.contains('403')) return 'You are not authorized rucker. Please log in again.';
  if (e.contains('404')) return 'Resource not found.';
  if (e.contains('timeout')) return 'Network timeout. Please check your connection, rucker.';
  if (e.contains('network')) return 'Network error. Please check your connection, rucker.';
  if (e.contains('already exists') || e.contains('Rucker already registered')) {
    return 'An account already exists for this email. Please sign in instead.';
  }
  if (e.contains('invalid email')) return 'Please enter a valid email address, rucker.';
  if (e.contains('password too short')) return 'Your password must be at least 8 characters, rucker.';
  if (e.contains('weak password')) return 'Your password is too weak, rucker. Please choose a stronger one.';
  if (e.contains('email') && e.contains('required')) return 'Email is required, rucker.';
  if (e.contains('password') && e.contains('required')) return 'Password is required, rucker.';
  // Add more mappings as needed

  return 'An error occurred: $error';
}
