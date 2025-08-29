#!/usr/bin/env python3
"""
Calorie Method Comparison Analysis

Compare three calorie calculation methods against existing session data:
1. Current MET-based method (backend calculations.py)
2. New Mechanical method (Pandolf with GORUCK corrections)  
3. New Fusion method (HR + Mechanical with weather adjustments)
"""

import os
import sys
import psycopg2
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime
import json
import math

# Add RuckTracker to path
sys.path.append('/Users/rory/RuckingApp/RuckTracker')
from utils.calculations import calculate_calories as current_method

class CalorieComparison:
    def __init__(self):
        self.results = []
        
    def connect_db(self):
        """Connect to database"""
        db_url = os.getenv('DATABASE_URL', 'postgresql://postgres@localhost/rucking_db')
        return psycopg2.connect(db_url)

    def fetch_sessions(self, limit=100):
        """Fetch session data for analysis"""
        conn = self.connect_db()
        cursor = conn.cursor()
        
        query = """
        SELECT rs.id, rs.distance_km, rs.duration_seconds, rs.elevation_gain_m, 
               rs.elevation_loss_m, rs.calories_burned, rs.ruck_weight_kg,
               u.weight_kg as user_weight_kg, u.gender, u.age,
               COUNT(hr.id) as hr_count, AVG(hr.bpm) as avg_hr
        FROM ruck_session rs
        JOIN "user" u ON rs.user_id = u.id
        LEFT JOIN heart_rate_sample hr ON rs.id = hr.session_id
        WHERE rs.status = 'completed' AND rs.distance_km >= 1.0 
              AND rs.duration_seconds > 0 AND rs.calories_burned > 0
        GROUP BY rs.id, u.weight_kg, u.gender, u.age
        ORDER BY rs.completed_at DESC
        LIMIT %s
        """
        
        cursor.execute(query, (limit,))
        sessions = []
        
        for row in cursor.fetchall():
            session = {
                'id': row[0], 'distance_km': row[1], 'duration_seconds': row[2],
                'elevation_gain_m': row[3] or 0.0, 'elevation_loss_m': row[4] or 0.0,
                'calories_burned': row[5], 'ruck_weight_kg': row[6] or 0.0,
                'user_weight_kg': row[7], 'gender': row[8], 'age': row[9] or 30,
                'hr_count': row[10], 'avg_hr': row[11]
            }
            sessions.append(session)
            
        cursor.close()
        conn.close()
        return sessions

    def current_met_method(self, session):
        """Current MET-based method"""
        return current_method(
            user_weight_kg=session['user_weight_kg'],
            ruck_weight_kg=session['ruck_weight_kg'],
            distance_km=session['distance_km'],
            elevation_gain_m=session['elevation_gain_m'],
            duration_seconds=session['duration_seconds'],
            elevation_loss_m=session['elevation_loss_m'],
            gender=session['gender']
        )

    def mechanical_method(self, session):
        """New Mechanical method (Pandolf)"""
        speed_kmh = (session['distance_km'] / (session['duration_seconds'] / 3600.0))
        grade_pct = (session['elevation_gain_m'] / (session['distance_km'] * 1000)) * 100
        
        # Simplified Pandolf implementation
        v = min(3.0, speed_kmh / 3.6)  # m/s
        W = session['user_weight_kg']
        L = session['ruck_weight_kg']
        G = max(-20.0, min(grade_pct, 30.0))
        
        lw = (L / W) if W > 0 else 0.0
        term_load = 2.0 * (W + L) * (lw * lw)
        term_speed = (W + L) * (1.5 * v * v + 0.35 * v * G)
        M = 1.5 * W + term_load + term_speed
        
        # GORUCK adjustment
        if lw > 0 and speed_kmh > 3.2:  # 2mph
            base_adj = min(lw * 0.45, 0.15)
            speed_factor = min((speed_kmh - 3.2) / 3.2, 1.0)
            M *= (1.0 + base_adj * speed_factor)
        
        M = max(50.0, min(M, 800.0))
        kcal = (M / 4186.0) * session['duration_seconds']
        
        return max(0, kcal)

    def fusion_method(self, session):
        """New Fusion method"""
        mechanical = self.mechanical_method(session)
        
        # For now, fusion = mechanical (no HR data processing in this simplified version)
        fusion = mechanical
        
        # Weather adjustment (default = 1.0)
        fusion *= 1.0
        
        # Cap within ±15% of mechanical
        fusion = max(mechanical * 0.85, min(fusion, mechanical * 1.15))
        
        # Gender adjustment if unknown
        if not session.get('gender'):
            fusion *= 0.925
            
        return fusion

    def analyze_sessions(self, sessions):
        """Analyze all sessions"""
        results = []
        
        for session in sessions:
            try:
                current_cal = self.current_met_method(session)
                mechanical_cal = self.mechanical_method(session)
                fusion_cal = self.fusion_method(session)
                actual_cal = session['calories_burned']
                
                # Calculate percentage differences
                current_diff = ((current_cal - actual_cal) / actual_cal) * 100
                mechanical_diff = ((mechanical_cal - actual_cal) / actual_cal) * 100
                fusion_diff = ((fusion_cal - actual_cal) / actual_cal) * 100
                
                result = {
                    'session_id': session['id'],
                    'distance_km': session['distance_km'],
                    'duration_hours': session['duration_seconds'] / 3600.0,
                    'speed_kmh': session['distance_km'] / (session['duration_seconds'] / 3600.0),
                    'elevation_gain_m': session['elevation_gain_m'],
                    'ruck_weight_kg': session['ruck_weight_kg'],
                    'actual_calories': actual_cal,
                    'current_calories': current_cal,
                    'mechanical_calories': mechanical_cal,
                    'fusion_calories': fusion_cal,
                    'current_diff_pct': current_diff,
                    'mechanical_diff_pct': mechanical_diff,
                    'fusion_diff_pct': fusion_diff,
                    'mechanical_vs_current_pct': ((mechanical_cal - current_cal) / current_cal) * 100,
                    'fusion_vs_current_pct': ((fusion_cal - current_cal) / current_cal) * 100
                }
                results.append(result)
                
            except Exception as e:
                print(f"Error processing session {session['id']}: {e}")
                
        return pd.DataFrame(results)

    def generate_report(self, df):
        """Generate analysis report"""
        print("=" * 60)
        print("CALORIE METHOD COMPARISON ANALYSIS")
        print("=" * 60)
        print(f"Sessions analyzed: {len(df)}")
        print(f"Average distance: {df['distance_km'].mean():.2f} km")
        print(f"Average duration: {df['duration_hours'].mean():.2f} hours")
        print()
        
        print("ACCURACY vs STORED VALUES:")
        print("-" * 30)
        for method in ['current', 'mechanical', 'fusion']:
            col = f'{method}_diff_pct'
            mae = df[col].abs().mean()
            mean_err = df[col].mean()
            print(f"{method.upper()}: MAE {mae:.1f}%, Mean {mean_err:+.1f}%")
        print()
        
        print("METHOD COMPARISONS:")
        print("-" * 30)
        mech_vs_curr = df['mechanical_vs_current_pct'].mean()
        fusion_vs_curr = df['fusion_vs_current_pct'].mean()
        print(f"Mechanical vs Current: {mech_vs_curr:+.1f}% average")
        print(f"Fusion vs Current: {fusion_vs_curr:+.1f}% average")
        
        # Best method
        best_mae = float('inf')
        best_method = None
        for method in ['current', 'mechanical', 'fusion']:
            col = f'{method}_diff_pct'
            mae = df[col].abs().mean()
            if mae < best_mae:
                best_mae = mae
                best_method = method
                
        print(f"\nMost accurate: {best_method.upper()} ({best_mae:.1f}% MAE)")

def main():
    print("🔍 Analyzing calorie calculation methods...")
    
    comparison = CalorieComparison()
    sessions = comparison.fetch_sessions(limit=100)
    
    if not sessions:
        print("No sessions found!")
        return
        
    df = comparison.analyze_sessions(sessions)
    comparison.generate_report(df)
    
    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f'/Users/rory/RuckingApp/calorie_comparison_{timestamp}.csv'
    df.to_csv(filename, index=False)
    print(f"\n💾 Results saved to: {filename}")

if __name__ == "__main__":
    main()
