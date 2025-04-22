// Shared error message mapper for user-friendly errors
String mapFriendlyErrorMessage(String? error) {
  if (error == null) return 'An unexpected error occurred.';
  final e = error.toLowerCase();

  if (e.contains('500')) return 'Server error, please try again later.';
  if (e.contains('401') || e.contains('403')) return 'You are not authorized. Please log in again.';
  if (e.contains('404')) return 'Resource not found.';
  if (e.contains('timeout')) return 'Network timeout. Please check your connection.';
  if (e.contains('network')) return 'Network error. Please check your connection.';
  if (e.contains('already exists') || e.contains('user already registered')) {
    return 'An account already exists for this email. Please sign in instead.';
  }
  if (e.contains('invalid email')) return 'Please enter a valid email address.';
  if (e.contains('password too short')) return 'Your password must be at least 8 characters.';
  if (e.contains('weak password')) return 'Your password is too weak. Please choose a stronger one.';
  if (e.contains('email') && e.contains('required')) return 'Email is required.';
  if (e.contains('password') && e.contains('required')) return 'Password is required.';
  // Add more mappings as needed

  return 'An error occurred: $error';
}
