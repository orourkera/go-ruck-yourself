# /Users/rory/RuckingApp/RuckTracker/api/event_deeplinks.py
from flask import Flask, jsonify, request, render_template_string
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
    <title>Ruck Club</title>
    <meta name="apple-itunes-app" content="app-id=6744974620">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 40px; }
        .container { max-width: 400px; margin: 0 auto; }
        .logo { font-size: 24px; margin-bottom: 20px; }
        .message { margin: 20px 0; }
        .app-buttons { margin-top: 30px; }
        .app-button { display: inline-block; margin: 10px; padding: 12px 24px; 
                     background: #007AFF; color: white; text-decoration: none; 
                     border-radius: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🏃‍♂️ Ruck Club</div>
        <div class="message">
            <h2>Opening Club...</h2>
            <p>If the Ruck app doesn't open automatically, download it to join this club!</p>
        </div>
        <div class="app-buttons">
            <a href="https://apps.apple.com/app/id6744974620" class="app-button">Download for iOS</a>
            <a href="https://play.google.com/store/apps/details?id=com.getrucky.app" class="app-button">Download for Android</a>
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
        
        return render_template_string(html_template, club_id=club_id)

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
    <title>Ruck Event</title>
    <meta name="apple-itunes-app" content="app-id=6744974620">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 40px; }
        .container { max-width: 400px; margin: 0 auto; }
        .logo { font-size: 24px; margin-bottom: 20px; }
        .message { margin: 20px 0; }
        .app-buttons { margin-top: 30px; }
        .app-button { display: inline-block; margin: 10px; padding: 12px 24px; 
                     background: #007AFF; color: white; text-decoration: none; 
                     border-radius: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🎯 Ruck Event</div>
        <div class="message">
            <h2>Opening Event...</h2>
            <p>If the Ruck app doesn't open automatically, download it to join this event!</p>
        </div>
        <div class="app-buttons">
            <a href="https://apps.apple.com/app/id6744974620" class="app-button">Download for iOS</a>
            <a href="https://play.google.com/store/apps/details?id=com.getrucky.app" class="app-button">Download for Android</a>
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
        
        return render_template_string(html_template, event_id=event_id)

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
                            "appIDs": ["73323J2N3Y.com.getrucky.app"],
                            "components": [
                                {
                                    "/": "/events/*",
                                    "comment": "Event deeplinks"
                                },
                                {
                                    "/": "/clubs/*",
                                    "comment": "Club deeplinks"
                                },
                                {
                                    "/": "/auth/callback", 
                                    "comment": "Auth callback"
                                }
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