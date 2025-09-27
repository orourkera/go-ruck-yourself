web: gunicorn RuckTracker.app:app --access-logfile - --log-level info --workers 2 --threads 4 --timeout 120
worker: python RuckTracker/background_scheduler.py