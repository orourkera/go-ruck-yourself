// Artillery load test helper functions for active rucking sessions
module.exports = {
  generateLocationBatch,
  generateRandomLocation,
  generateHeartRateBatch
};

// Base coordinates (around Central Park, NYC for realistic testing)
const BASE_LAT = 40.7829;
const BASE_LNG = -73.9654;

// Generate a batch of realistic location points
function generateLocationBatch(context, events, done) {
  const batchSize = context.vars.batchSize || 5; // Default 5 points per batch
  const points = [];
  
  // Simulate movement over time with realistic GPS coordinates
  for (let i = 0; i < batchSize; i++) {
    const point = {
      latitude: BASE_LAT + (Math.random() - 0.5) * 0.01, // ~500m radius variation
      longitude: BASE_LNG + (Math.random() - 0.5) * 0.01,
      elevation_meters: 50 + Math.random() * 100, // Realistic elevation 50-150m
      timestamp: new Date(Date.now() - (batchSize - i) * 10000).toISOString(), // 10 seconds apart
      accuracy: 5 + Math.random() * 10 // GPS accuracy 5-15 meters
    };
    points.push(point);
  }
  
  context.vars.locationBatch = points;
  return done();
}

// Generate single location point
function generateRandomLocation(context, events, done) {
  const location = {
    latitude: BASE_LAT + (Math.random() - 0.5) * 0.02,
    longitude: BASE_LNG + (Math.random() - 0.5) * 0.02,
    elevation_meters: 30 + Math.random() * 200,
    timestamp: new Date().toISOString(),
    accuracy: 3 + Math.random() * 12
  };
  
  context.vars.location = location;
  return done();
}

// Generate batch of heart rate samples (if your app supports this)
function generateHeartRateBatch(context, events, done) {
  const batchSize = context.vars.heartRateBatchSize || 10;
  const heartRateSamples = [];
  
  // Simulate realistic heart rate during exercise (120-180 BPM)
  const baseHeartRate = 140;
  
  for (let i = 0; i < batchSize; i++) {
    const sample = {
      heart_rate_bpm: baseHeartRate + (Math.random() - 0.5) * 40, // 120-180 range
      timestamp: new Date(Date.now() - (batchSize - i) * 5000).toISOString(), // 5 seconds apart
      source: "apple_watch" // or "chest_strap", "wrist_sensor", etc.
    };
    heartRateSamples.push(sample);
  }
  
  context.vars.heartRateBatch = heartRateSamples;
  return done();
}

// Helper function to simulate realistic session duration
function generateSessionDuration(context, events, done) {
  // Generate realistic ruck duration: 30 minutes to 3 hours
  const durationMinutes = 30 + Math.random() * 150; // 30-180 minutes
  const durationSeconds = Math.floor(durationMinutes * 60);
  
  context.vars.sessionDurationSeconds = durationSeconds;
  context.vars.sessionDurationMinutes = Math.floor(durationMinutes);
  
  return done();
}
