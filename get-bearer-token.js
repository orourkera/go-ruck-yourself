#!/usr/bin/env node

// Script to get a bearer token for load testing
const https = require('https');
const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

console.log('🔐 Ruck App Bearer Token Generator');
console.log('===================================');
console.log('');

// Get credentials from user
rl.question('Enter your email: ', (email) => {
  rl.question('Enter your password: ', (password) => {
    rl.close();
    
    // Sign in to get token
    signIn(email, password);
  });
});

function signIn(email, password) {
  const postData = JSON.stringify({
    email: email,
    password: password
  });

  const options = {
    hostname: 'getrucky.com',
    port: 443,
    path: '/api/auth/signin',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(postData),
      'User-Agent': 'Ruck-Token-Generator/1.0'
    }
  };

  console.log('🔄 Signing in to get bearer token...');

  const req = https.request(options, (res) => {
    let data = '';

    res.on('data', (chunk) => {
      data += chunk;
    });

    res.on('end', () => {
      try {
        const response = JSON.parse(data);
        
        const token = response.token || response.access_token;
        if (res.statusCode === 200 && token) {
          console.log('✅ Success! Bearer token obtained:');
          console.log('');
          console.log('BEARER_TOKEN=' + token);
          console.log('');
          console.log('💡 To use with load tests:');
          console.log('export BEARER_TOKEN="' + token + '"');
          console.log('artillery run load-test-ruck.yml');
          console.log('');
          if (response.expires_in) {
            console.log('⏰ Token expires in:', response.expires_in, 'seconds');
          }
          
          // Save to .env file for convenience
          const fs = require('fs');
          fs.writeFileSync('.env.loadtest', `BEARER_TOKEN=${token}\n`);
          console.log('📝 Token saved to .env.loadtest file');
          
        } else {
          console.error('❌ Sign-in failed:');
          console.error('Status:', res.statusCode);
          console.error('Response:', response);
        }
      } catch (e) {
        console.error('❌ Error parsing response:', e.message);
        console.error('Raw response:', data);
      }
    });
  });

  req.on('error', (e) => {
    console.error('❌ Request failed:', e.message);
  });

  req.write(postData);
  req.end();
}
