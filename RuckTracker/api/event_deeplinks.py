# /Users/rory/RuckingApp/RuckTracker/api/event_deeplinks.py
from flask import Flask, jsonify, request, render_template_string, make_response
from flask_restful import Api, Resource
import os

class ClubDeeplinkResource(Resource):
    def get(self, club_id):
        """
        Handle club deeplinks - returns HTML page that redirects to app stores
        if the app is not installed, or opens the app if it is installed.
        """
        
        # HTML template for club landing page
        html_template = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Join This Ruck Club</title>
    <meta name="apple-itunes-app" content="app-id=6744974620">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    
    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="website">
    <meta property="og:url" content="https://getrucky.com/clubs/{{ club_id }}">
    <meta property="og:title" content="Join This Ruck Club">
    <meta property="og:description" content="Join our rucking community! Download the Ruck app to connect with fellow ruckers, track your workouts, and join group events.">
    <meta property="og:image" content="https://getrucky.com/static/images/og_preview.png">
    <meta property="og:image:width" content="1200">
    <meta property="og:image:height" content="630">
    <meta property="og:image:alt" content="Ruck Club - Join the Community">
    
    <!-- General Meta -->
    <meta name="description" content="Join our rucking community! Download the Ruck app to connect with fellow ruckers, track your workouts, and join group events.">
    <meta name="author" content="Ruck App">
    <meta name="robots" content="index, follow">
    <link href="https://fonts.googleapis.com/css2?family=Bangers&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
    
    <!-- Twitter -->
    <meta property="twitter:card" content="summary_large_image">
    <meta property="twitter:url" content="https://getrucky.com/clubs/{{ club_id }}">
    <meta property="twitter:title" content="Join This Ruck Club">
    <meta property="twitter:description" content="Join our rucking community! Download the Ruck app to connect with fellow ruckers, track your workouts, and join group events.">
    <meta property="twitter:image" content="https://getrucky.com/static/images/og_preview.png">
    <style>
        body { 
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif; 
            text-align: center; 
            padding: 40px 20px; 
            margin: 0;
            background: linear-gradient(135deg, #728C69 0%, #546A4A 100%);
            color: white;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container { 
            max-width: 400px; 
            margin: 0 auto; 
        }
        .message { 
            margin: 30px 0; 
        }
        .message h2 { 
            font-family: 'Bangers', cursive;
            font-size: 36px; 
            margin-bottom: 16px; 
            color: white;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.3);
        }
        .message p { 
            font-size: 18px; 
            margin: 16px 0; 
            color: rgba(255,255,255,0.9);
            line-height: 1.5;
        }
        .app-buttons { 
            margin-top: 40px; 
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 16px;
        }
        .app-button { 
            display: block;
            width: 200px;
            height: auto;
            transition: transform 0.2s ease, opacity 0.2s ease;
        }
        .app-button:hover {
            transform: scale(1.05);
            opacity: 0.9;
        }
        .mascot-image {
            width: 80px;
            height: auto;
            margin-bottom: 16px;
        }
    </style>
</head>
<body>
    <div class="container">
        <img src="/static/images/go ruck yourself.png" alt="Go Ruck Yourself" class="mascot-image">
        <div class="message">
            <h2>Opening Club...</h2>
            <p>If the Ruck app doesn't open automatically, download it to join this club!</p>
        </div>
        <div class="app-buttons">
            <a href="https://apps.apple.com/app/id6744974620">
                <img src="/static/images/app-store-badge.png" alt="Download on the App Store" class="app-button">
            </a>
            <a href="https://play.google.com/store/apps/details?id=com.getrucky.app">
                <img src="/static/images/google-play-badge.png" alt="Get it on Google Play" class="app-button">
            </a>
        </div>
    </div>
    
    <script>
        // Try to open the app after a short delay
        setTimeout(() => {
            const userAgent = navigator.userAgent;
            if (/iPad|iPhone|iPod/.test(userAgent)) {
                window.location.href = "https://apps.apple.com/app/id6744974620";
            } else if (/Android/.test(userAgent)) {
                window.location.href = "https://play.google.com/store/apps/details?id=com.getrucky.app";
            }
        }, 3000);
    </script>
</body>
</html>
        """
        
        response = make_response(render_template_string(html_template, club_id=club_id))
        response.headers['Content-Type'] = 'text/html'
        return response

class EventDeeplinkResource(Resource):
    def get(self, event_id):
        """
        Handle event deeplinks - returns HTML page that redirects to app stores
        if the app is not installed, or opens the app if it is installed.
        """
        
        # HTML template for event landing page
        html_template = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Join This Ruck Event</title>
    <meta name="apple-itunes-app" content="app-id=6744974620">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    
    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="event">
    <meta property="og:url" content="https://getrucky.com/events/{{ event_id }}">
    <meta property="og:title" content="Join This Ruck Event">
    <meta property="og:description" content="You're invited to join a ruck event! Download the Ruck app to RSVP, track your progress, and connect with other participants.">
    <meta property="og:image" content="https://getrucky.com/static/images/og_preview.png">
    <meta property="og:image:width" content="1200">
    <meta property="og:image:height" content="630">
    <meta property="og:image:alt" content="Ruck Event - Join the Challenge">
    
    <!-- General Meta -->
    <meta name="description" content="You're invited to join a ruck event! Download the Ruck app to RSVP, track your progress, and connect with other participants.">
    <meta name="author" content="Ruck App">
    <meta name="robots" content="index, follow">
    <link href="https://fonts.googleapis.com/css2?family=Bangers&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
    
    <!-- Twitter -->
    <meta property="twitter:card" content="summary_large_image">
    <meta property="twitter:url" content="https://getrucky.com/events/{{ event_id }}">
    <meta property="twitter:title" content="Join This Ruck Event">
    <meta property="twitter:description" content="You're invited to join a ruck event! Download the Ruck app to RSVP, track your progress, and connect with other participants.">
    <meta property="twitter:image" content="https://getrucky.com/static/images/og_preview.png">
    <style>
        body { 
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif; 
            text-align: center; 
            padding: 40px 20px; 
            margin: 0;
            background: linear-gradient(135deg, #728C69 0%, #546A4A 100%);
            color: white;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container { 
            max-width: 400px; 
            margin: 0 auto; 
        }
        .logo { 
            font-family: 'Bangers', cursive;
            font-size: 48px; 
            margin-bottom: 20px; 
            color: white;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .message { 
            margin: 30px 0; 
        }
        .message h2 { 
            font-family: 'Bangers', cursive;
            font-size: 36px; 
            margin-bottom: 16px; 
            color: white;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.3);
        }
        .message p { 
            font-size: 18px; 
            margin: 16px 0; 
            color: rgba(255,255,255,0.9);
            line-height: 1.5;
        }
        .app-buttons { 
            margin-top: 40px; 
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 16px;
        }
        .app-button { 
            display: block;
            width: 200px;
            height: auto;
            transition: transform 0.2s ease, opacity 0.2s ease;
        }
        .app-button:hover {
            transform: scale(1.05);
            opacity: 0.9;
        }
        .target-emoji {
            font-size: 40px;
            margin-bottom: 16px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="target-emoji">🎯</div>
        <div class="logo">Ruck Event</div>
        <div class="message">
            <h2>Opening Event...</h2>
            <p>If the Ruck app doesn't open automatically, download it to join this event!</p>
        </div>
        <div class="app-buttons">
            <a href="https://apps.apple.com/app/id6744974620">
                <img src="/static/images/app-store-badge.png" alt="Download on the App Store" class="app-button">
            </a>
            <a href="https://play.google.com/store/apps/details?id=com.getrucky.app">
                <img src="/static/images/google-play-badge.png" alt="Get it on Google Play" class="app-button">
            </a>
        </div>
    </div>
    
    <script>
        // Try to open the app after a short delay
        setTimeout(() => {
            const userAgent = navigator.userAgent;
            if (/iPad|iPhone|iPod/.test(userAgent)) {
                window.location.href = "https://apps.apple.com/app/id6744974620";
            } else if (/Android/.test(userAgent)) {
                window.location.href = "https://play.google.com/store/apps/details?id=com.getrucky.app";
            }
        }, 3000);
    </script>
</body>
</html>
        """
        
        response = make_response(render_template_string(html_template, event_id=event_id))
        response.headers['Content-Type'] = 'text/html'
        return response

class WellKnownResource(Resource):
    def get(self, filename):
        """
        Serve .well-known files for Universal Links and App Links
        """
        if filename == 'apple-app-site-association':
            return {
                "applinks": {
                    "details": [
                        {
                            "appID": "73323J2N3Y.com.getrucky.app",
                            "paths": [
                                "/events/*",
                                "/clubs/*",
                                "/auth/callback",
                                "*"
                            ]
                        }
                    ]
                },
                "webcredentials": {
                    "apps": ["73323J2N3Y.com.getrucky.app"]
                }
            }
        elif filename == 'assetlinks.json':
            return [{
                "relation": ["delegate_permission/common.handle_all_urls"],
                "target": {
                    "namespace": "android_app",
                    "package_name": "com.getrucky.app",
                    "sha256_cert_fingerprints": ["2A:E7:B5:C9:26:B6:5E:99:7B:08:07:C5:63:01:43:82:BC:6C:6E:51:EB:81:FD:B7:EE:A0:40:AE:D4:47:BB:7B"]
                }
            }]
        
        return {"error": "File not found"}, 404

# Register the routes
def register_deeplink_routes(api):
    api.add_resource(ClubDeeplinkResource, '/clubs/<string:club_id>')
    api.add_resource(EventDeeplinkResource, '/events/<string:event_id>')
    api.add_resource(WellKnownResource, '/.well-known/<string:filename>')