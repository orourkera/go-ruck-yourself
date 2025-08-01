"""
OpenWeatherMap API integration for weather forecasts.
Provides current weather and forecasts using OpenWeatherMap service.
"""

import os
import requests
from datetime import datetime, timedelta
from flask import request, jsonify, g
from flask_restful import Resource
import logging

from ..utils.auth_helper import get_current_user_id

logger = logging.getLogger(__name__)

class WeatherResource(Resource):
    """Handle weather forecast requests using OpenWeatherMap."""
    
    def __init__(self):
        # OpenWeatherMap configuration
        self.api_key = os.getenv('OPENWEATHER_API_KEY')
        self.base_url = "https://api.openweathermap.org/data/2.5"
        
        if not self.api_key:
            logger.error("Missing OpenWeatherMap API key (OPENWEATHER_API_KEY)")
        else:
            logger.info("OpenWeatherMap configuration complete")
    
    def get(self):
        """Get weather forecast for a location and date."""
        try:
            if not hasattr(g, 'user') or g.user is None:
                return {
                    "success": False,
                    "message": "Authentication required"
                }, 401
            
            if not self.api_key:
                return {
                    "success": False,
                    "message": "OpenWeatherMap API key not configured"
                }, 500
            
            # Get query parameters
            latitude = request.args.get('latitude', type=float)
            longitude = request.args.get('longitude', type=float)
            datasets = request.args.get('datasets', 'currentWeather,hourlyForecast,dailyForecast').split(',')
            
            if latitude is None or longitude is None:
                return {
                    "success": False,
                    "message": "latitude and longitude parameters are required"
                }, 400
            
            logger.info(f"Fetching weather for coordinates: {latitude}, {longitude}")
            
            # Make OpenWeatherMap API requests
            weather_data = {}
            
            # Get current weather if requested
            if 'currentWeather' in datasets:
                current = self._get_current_weather(latitude, longitude)
                if current:
                    weather_data['currentWeather'] = current
            
            # Get hourly forecast if requested
            if 'hourlyForecast' in datasets:
                hourly = self._get_hourly_forecast(latitude, longitude)
                if hourly:
                    weather_data['hourlyForecast'] = hourly
            
            # Get daily forecast if requested  
            if 'dailyForecast' in datasets:
                daily = self._get_daily_forecast(latitude, longitude)
                if daily:
                    weather_data['dailyForecast'] = daily
            
            # Log final weather data before returning
            logger.info(f"Final weather data keys: {list(weather_data.keys())}")
            
            # Return error if no data was retrieved
            if not weather_data:
                logger.warning("No weather data retrieved from any dataset")
                return {
                    "success": False,
                    "message": "No weather data available",
                    "debug": "All OpenWeatherMap API calls returned empty data"
                }, 200
            
            return weather_data, 200
            
        except Exception as e:
            logger.error(f"Error fetching weather data: {e}")
            return {
                "success": False,
                "message": "Failed to fetch weather data"
            }, 500
    
    def _get_current_weather(self, latitude, longitude):
        """Get current weather conditions from OpenWeatherMap."""
        try:
            url = f"{self.base_url}/weather"
            
            params = {
                'lat': latitude,
                'lon': longitude,
                'appid': self.api_key,
                'units': 'metric'  # Celsius, m/s for wind
            }
            
            logger.info(f"Making OpenWeatherMap current weather request")
            response = requests.get(url, params=params, timeout=30)
            
            logger.info(f"OpenWeatherMap response status: {response.status_code}")
            
            if response.status_code == 200:
                data = response.json()
                logger.info(f"Current weather data retrieved successfully")
                return self._format_current_weather(data)
            else:
                logger.warning(f"Current weather API returned {response.status_code}: {response.text}")
                return None
                
        except Exception as e:
            logger.error(f"Error fetching current weather: {e}")
            return None
    
    def _get_hourly_forecast(self, latitude, longitude):
        """Get hourly weather forecast from OpenWeatherMap."""
        try:
            url = f"{self.base_url}/forecast"
            
            params = {
                'lat': latitude,
                'lon': longitude,
                'appid': self.api_key,
                'units': 'metric'
            }
            
            logger.info(f"Making OpenWeatherMap hourly forecast request")
            response = requests.get(url, params=params, timeout=30)
            
            logger.info(f"OpenWeatherMap hourly response status: {response.status_code}")
            
            if response.status_code == 200:
                data = response.json()
                logger.info(f"Hourly forecast data retrieved successfully")
                return self._format_hourly_forecast(data)
            else:
                logger.warning(f"Hourly forecast API returned {response.status_code}: {response.text}")
                return None
                
        except Exception as e:
            logger.error(f"Error fetching hourly forecast: {e}")
            return None
    
    def _get_daily_forecast(self, latitude, longitude):
        """Get daily weather forecast from OpenWeatherMap."""
        try:
            # Use One Call API for daily forecast (requires subscription for 3.0, using 2.5)
            url = f"{self.base_url}/forecast/daily"
            
            params = {
                'lat': latitude,
                'lon': longitude,
                'appid': self.api_key,
                'units': 'metric',
                'cnt': 3  # Next 3 days
            }
            
            logger.info(f"Making OpenWeatherMap daily forecast request")
            response = requests.get(url, params=params, timeout=30)
            
            logger.info(f"OpenWeatherMap daily response status: {response.status_code}")
            
            if response.status_code == 200:
                data = response.json()
                logger.info(f"Daily forecast data retrieved successfully")
                return self._format_daily_forecast(data)
            else:
                logger.warning(f"Daily forecast API returned {response.status_code}: {response.text}")
                return None
                
        except Exception as e:
            logger.error(f"Error fetching daily forecast: {e}")
            return None
    
    def _format_current_weather(self, data):
        """Format OpenWeatherMap current weather data to match our expected structure."""
        try:
            return {
                'temperature': data['main']['temp'],
                'humidity': data['main']['humidity'],
                'pressure': data['main']['pressure'],
                'windSpeed': data['wind']['speed'],
                'windDirection': data['wind'].get('deg', 0),
                'cloudCover': data['clouds']['all'] / 100.0,  # Convert percentage to decimal
                'visibility': data.get('visibility', 10000) / 1000.0,  # Convert m to km
                'conditionCode': data['weather'][0]['id'],
                'condition': data['weather'][0]['description'].title(),
                'uvIndex': data.get('uvi', 0),  # May not be available in basic plan
                'precipitationIntensity': 0,  # Not available in current weather
                'precipitationChance': 0
            }
        except Exception as e:
            logger.error(f"Error formatting current weather data: {e}")
            return None
    
    def _format_hourly_forecast(self, data):
        """Format OpenWeatherMap hourly forecast data."""
        try:
            hours = []
            for item in data['list'][:24]:  # Next 24 hours
                hours.append({
                    'forecastStart': datetime.fromtimestamp(item['dt']).isoformat(),
                    'temperature': item['main']['temp'],
                    'humidity': item['main']['humidity'],
                    'pressure': item['main']['pressure'],
                    'windSpeed': item['wind']['speed'],
                    'windDirection': item['wind'].get('deg', 0),
                    'cloudCover': item['clouds']['all'] / 100.0,
                    'conditionCode': item['weather'][0]['id'],
                    'condition': item['weather'][0]['description'].title(),
                    'precipitationChance': item.get('pop', 0) * 100,  # Probability of precipitation
                    'precipitationIntensity': item.get('rain', {}).get('3h', 0) / 3.0  # mm/h
                })
            return {'hours': hours}
        except Exception as e:
            logger.error(f"Error formatting hourly forecast data: {e}")
            return None
    
    def _format_daily_forecast(self, data):
        """Format OpenWeatherMap daily forecast data."""
        try:
            days = []
            for item in data.get('list', []):
                days.append({
                    'forecastStart': datetime.fromtimestamp(item['dt']).isoformat(),
                    'temperatureMax': item['temp']['max'],
                    'temperatureMin': item['temp']['min'],
                    'humidity': item['humidity'],
                    'pressure': item['pressure'],
                    'windSpeed': item['speed'],
                    'windDirection': item.get('deg', 0),
                    'cloudCover': item['clouds'] / 100.0,
                    'conditionCode': item['weather'][0]['id'],
                    'condition': item['weather'][0]['description'].title(),
                    'precipitationChance': item.get('pop', 0) * 100,
                    'precipitationIntensity': item.get('rain', 0)
                })
            return {'days': days}
        except Exception as e:
            logger.error(f"Error formatting daily forecast data: {e}")
            return None
