# Add this to your Flask app (e.g., in app.py or create a new route file)

from flask import Blueprint, request, jsonify
from services.push_notification_service import PushNotificationService
import logging

# Create blueprint for test routes
test_bp = Blueprint('test', __name__)

@test_bp.route('/test/push-notification', methods=['POST'])
def test_push_notification():
    """
    Test endpoint for push notifications
    
    Send POST request with JSON:
    {
        "fcm_token": "your_fcm_token_here",
        "title": "Test Title",
        "body": "Test Body"
    }
    """
    try:
        data = request.json
        
        if not data or 'fcm_token' not in data:
            return jsonify({
                'error': 'fcm_token is required',
                'example': {
                    'fcm_token': 'your_fcm_token_here',
                    'title': 'Optional Test Title',
                    'body': 'Optional Test Body'
                }
            }), 400
        
        fcm_token = data['fcm_token']
        title = data.get('title', 'Test Notification 🧪')
        body = data.get('body', 'This is a test from your backend!')
        
        # Initialize push service
        push_service = PushNotificationService()
        
        # Send notification
        success = push_service.send_notification(
            device_tokens=[fcm_token],
            title=title,
            body=body,
            notification_data={
                'test': 'true',
                'source': 'test_endpoint',
                'timestamp': str(time.time())
            }
        )
        
        if success:
            return jsonify({
                'success': True,
                'message': 'Notification sent successfully!',
                'token_preview': fcm_token[:20] + '...'
            })
        else:
            return jsonify({
                'success': False,
                'message': 'Failed to send notification'
            }), 500
            
    except Exception as e:
        logging.error(f"Push notification test error: {e}", exc_info=True)
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# Don't forget to register this blueprint in your main app:
# app.register_blueprint(test_bp)
