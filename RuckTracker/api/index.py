from flask import Flask, request
import sys
import os

# Add the parent directory to sys.path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app

def handler(request):
    """Handle incoming requests for Vercel serverless deployment"""
    return app(request)
