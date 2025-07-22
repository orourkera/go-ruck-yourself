// Artillery load test helper functions
module.exports = {
  getRandomUserId
};

// Simulate getting a random user ID for profile viewing
// In a real scenario, you'd pull this from actual user data
function getRandomUserId(context, events, done) {
  // Common user IDs from your leaderboard (you can update these)
  const userIds = [
    'user_123', 'user_456', 'user_789', 
    'user_abc', 'user_def', 'user_ghi'
  ];
  
  context.vars.userId = userIds[Math.floor(Math.random() * userIds.length)];
  return done();
}
