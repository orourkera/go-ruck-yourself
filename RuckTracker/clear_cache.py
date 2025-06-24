#!/usr/bin/env python3
import os
import redis

redis_url = os.environ.get('REDIS_URL')
if redis_url:
    r = redis.from_url(redis_url)
    keys = r.keys('ruck_session:*')
    if keys:
        r.delete(*keys)
        print(f'Cleared {len(keys)} ruck session cache keys')
    else:
        print('No ruck session cache keys found')
else:
    print('REDIS_URL not found')
