"""
WeatherKit API integration for weather forecasts.
Provides current weather and forecasts using Apple's WeatherKit service.
"""

import os
import jwt
import time
import requests
from datetime import datetime, timedelta
from flask import request, jsonify, g
from flask_restful import Resource
import logging

from ..utils.auth_helper import get_current_user_id

logger = logging.getLogger(__name__)

class WeatherResource(Resource):
    """Handle weather forecast requests using WeatherKit."""
    
    def __init__(self):
        # WeatherKit configuration
        self.team_id = os.getenv('APPLE_TEAM_ID')
        self.service_id = os.getenv('APPLE_SERVICE_ID') 
        self.key_id = os.getenv('APPLE_KEY_ID')
        self.private_key = os.getenv('APPLE_PRIVATE_KEY', '').replace('\\n', '\n')
        self.base_url = "https://weatherkit.apple.com/api/v1"
        
        if not all([self.team_id, self.service_id, self.key_id, self.private_key]):
            logger.error("Missing WeatherKit configuration")
    
    def get(self):
        """Get weather forecast for a location and date."""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {
                    "success": False,
                    "message": "Authentication required"
                }, 401
            
            # Get query parameters
            latitude = request.args.get('latitude', type=float)
            longitude = request.args.get('longitude', type=float)
            date_str = request.args.get('date')
            datasets = request.args.get('datasets', 'currentWeather,hourlyForecast,dailyForecast').split(',')
            
            if latitude is None or longitude is None:
                return {
                    "success": False,
                    "message": "latitude and longitude parameters are required"
                }, 400
            
            # Parse target date
            target_date = datetime.now()
            if date_str:
                try:
                    target_date = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
                except ValueError:
                    logger.warning(f"Invalid date format: {date_str}")
            
            # Generate WeatherKit JWT token
            token = self._generate_jwt_token()
            if not token:
                return {
                    "success": False,
                    "message": "Failed to generate authentication token"
                }, 500
            
            # Make WeatherKit API requests
            weather_data = {}
            
            # Get current weather if requested
            if 'currentWeather' in datasets:
                current = self._get_current_weather(token, latitude, longitude)
                if current:
                    weather_data['currentWeather'] = current
            
            # Get hourly forecast if requested
            if 'hourlyForecast' in datasets:
                hourly = self._get_hourly_forecast(token, latitude, longitude, target_date)
                if hourly:
                    weather_data['hourlyForecast'] = hourly
            
            # Get daily forecast if requested  
            if 'dailyForecast' in datasets:
                daily = self._get_daily_forecast(token, latitude, longitude, target_date)
                if daily:
                    weather_data['dailyForecast'] = daily
            
            return weather_data, 200
            
        except Exception as e:
            logger.error(f"Error fetching weather data: {e}")
            return {
                "success": False,
                "message": "Failed to fetch weather data"
            }, 500
    
    def _generate_jwt_token(self):
        """Generate JWT token for WeatherKit API authentication."""
        try:
            # Current time
            now = int(time.time())
            
            # JWT payload
            payload = {
                'iss': self.team_id,
                'iat': now,
                'exp': now + 3600,  # Token expires in 1 hour
                'sub': self.service_id,
            }
            
            # JWT headers
            headers = {
                'alg': 'ES256',
                'kid': self.key_id,
                'id': f"{self.team_id}.{self.service_id}"
            }
            
            # Generate token
            token = jwt.encode(payload, self.private_key, algorithm='ES256', headers=headers)
            return token
            
        except Exception as e:
            logger.error(f"Failed to generate JWT token: {e}")
            return None
    
    def _get_current_weather(self, token, latitude, longitude):
        """Get current weather conditions."""
        try:
            url = f"{self.base_url}/weather/{self.get_language()}/{latitude}/{longitude}/current"
            
            headers = {
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            }
            
            response = requests.get(url, headers=headers, timeout=30)
            
            if response.status_code == 200:
                return response.json()
            else:
                logger.warning(f"Current weather API returned {response.status_code}: {response.text}")
                return None
                
        except Exception as e:
            logger.error(f"Error fetching current weather: {e}")
            return None
    
    def _get_hourly_forecast(self, token, latitude, longitude, target_date):
        """Get hourly weather forecast."""
        try:
            # Get hourly forecast for next 24 hours from target date
            end_date = target_date + timedelta(hours=24)
            
            url = f"{self.base_url}/weather/{self.get_language()}/{latitude}/{longitude}/forecast/hourly"
            
            headers = {
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            }
            
            params = {
                'dataSets': 'forecastHourly',
                'hourlyStart': target_date.isoformat(),
                'hourlyEnd': end_date.isoformat(),
            }
            
            response = requests.get(url, headers=headers, params=params, timeout=30)
            
            if response.status_code == 200:
                data = response.json()
                return data.get('forecastHourly', {}).get('hours', [])
            else:
                logger.warning(f"Hourly forecast API returned {response.status_code}: {response.text}")
                return None
                
        except Exception as e:
            logger.error(f"Error fetching hourly forecast: {e}")
            return None
    
    def _get_daily_forecast(self, token, latitude, longitude, target_date):
        """Get daily weather forecast."""
        try:
            # Get daily forecast for next 3 days from target date
            end_date = target_date + timedelta(days=3)
            
            url = f"{self.base_url}/weather/{self.get_language()}/{latitude}/{longitude}/forecast/daily"
            
            headers = {
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            }
            
            params = {
                'dataSets': 'forecastDaily',
                'dailyStart': target_date.date().isoformat(),
                'dailyEnd': end_date.date().isoformat(),
            }
            
            response = requests.get(url, headers=headers, params=params, timeout=30)
            
            if response.status_code == 200:
                data = response.json()
                return data.get('forecastDaily', {}).get('days', [])
            else:
                logger.warning(f"Daily forecast API returned {response.status_code}: {response.text}")
                return None
                
        except Exception as e:
            logger.error(f"Error fetching daily forecast: {e}")
            return None
    
    def get_language(self):
        """Get language code for API requests."""
        # Default to English, could be made configurable
        return 'en'
