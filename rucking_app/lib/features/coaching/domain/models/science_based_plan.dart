class ScienceBasedPlan {
  final String planId;
  final String name;
  final int durationWeeks;
  final Map<String, dynamic> baseStructure;
  final Map<String, dynamic> personalizationKnobs;
  final Map<String, dynamic> progressionRules;
  final Map<String, dynamic> nonNegotiables;
  final Map<String, dynamic> retests;

  const ScienceBasedPlan({
    required this.planId,
    required this.name,
    required this.durationWeeks,
    required this.baseStructure,
    required this.personalizationKnobs,
    required this.progressionRules,
    required this.nonNegotiables,
    required this.retests,
  });

  Map<String, dynamic> toJson() {
    return {
      'planId': planId,
      'name': name,
      'durationWeeks': durationWeeks,
      'baseStructure': baseStructure,
      'personalizationKnobs': personalizationKnobs,
      'progressionRules': progressionRules,
      'nonNegotiables': nonNegotiables,
      'retests': retests,
    };
  }

  factory ScienceBasedPlan.fromJson(Map<String, dynamic> json) {
    return ScienceBasedPlan(
      planId: json['planId'] as String,
      name: json['name'] as String,
      durationWeeks: json['durationWeeks'] as int,
      baseStructure: json['baseStructure'] as Map<String, dynamic>,
      personalizationKnobs: json['personalizationKnobs'] as Map<String, dynamic>,
      progressionRules: json['progressionRules'] as Map<String, dynamic>,
      nonNegotiables: json['nonNegotiables'] as Map<String, dynamic>,
      retests: json['retests'] as Map<String, dynamic>,
    );
  }

  static const List<ScienceBasedPlan> basePlans = [
    ScienceBasedPlan(
      planId: 'fat-loss',
      name: 'Fat Loss & Feel Better',
      durationWeeks: 12,
      baseStructure: {
        'sessionsPerWeek': {
          'rucks': 3,
          'unloadedCardio': 2,
          'strength': 2,
        },
        'strengthDuration': '30-35 min',
        'startingLoad': {
          'percentage': '10-15% bodyweight',
          'cap': '18 kg / 40 lb',
        },
        'weeklyRuckMinutes': {
          'start': '120-150',
          'end': '170-200',
        },
        'intensity': {
          'z2': '40-59% HRR (RPE 3-4)',
        },
      },
      progressionRules: {
        'oneKnobPerWeek': true,
        'options': [
          '+5-10 min to one ruck',
          '+50-100 m vert on one ruck',
          '+1-2% BW every 2-3 weeks if recovery green',
        ],
        'deload': {
          'frequency': 'every 4th week',
          'reduction': '≈-30% ruck minutes',
        },
      },
      nonNegotiables: {
        'ruckFrequencyCap': '≤4/week',
        'repeatWeekIf': [
          'HR drift is high',
          'RPE >5',
          'next-day joints aren\'t normal',
        ],
      },
      retests: {
        'bodyMass': 'weekly',
        '30minRuckTT': 'weeks 0/6/12',
      },
      personalizationKnobs: {
        'timeBudget': true,
        'scheduledDays': true,
        'equipment': true,
        'safeStartingLoad': true,
        'terrainAccess': true,
        'intensityControl': true,
        'riskProfile': true,
        'routeWeatherSwaps': true,
      },
    ),

    ScienceBasedPlan(
      planId: 'get-faster',
      name: 'Get Faster at Rucking',
      durationWeeks: 8,
      baseStructure: {
        'sessionsPerWeek': {
          'rucks': 3,
          'unloadedCardio': 1,
        },
        'ruckTypes': {
          'A_Z2Duration': '45→70 min',
          'B_Tempo': '20-35 min "comfortably hard" in 40-55 min session',
          'C_HillsZ2': '40-60 min; +50-100 m vert/week if green',
        },
        'startingLoad': {
          'percentage': '10-15% BW',
          'holdUntil': '≥week 3',
        },
        'intensity': {
          'z2': '40-59% HRR / RPE 3-4',
          'tempo': '≈60-70% HRR / RPE 6-7',
        },
      },
      progressionRules: {
        'oneVariableAtATime': true,
        'deload': {
          'week': 4,
          'reduction': '≈-30% time/vert',
        },
        'noLoadBumpsOnTempoHillsDuringDeload': true,
      },
      nonNegotiables: {
        'progressOneVariableAtATime': true,
        'noLoadBumpsOnTempoHillsDuringDeload': true,
      },
      retests: {
        '60minRuck': 'week 8 at baseline load/route',
      },
      personalizationKnobs: {
        'timeBudget': true,
        'scheduledDays': true,
        'equipment': true,
        'safeStartingLoad': true,
        'terrainAccess': true,
        'intensityControl': true,
        'riskProfile': true,
        'routeWeatherSwaps': true,
      },
    ),

    ScienceBasedPlan(
      planId: 'event-prep',
      name: '12-mile under 3:00 (or custom event)',
      durationWeeks: 12,
      baseStructure: {
        'sessionsPerWeek': {
          'rucks': 3,
          'easyRunBike': 1,
        },
        'runBikeDuration': '30-45 min',
        'ruckTypes': {
          'intervals': '6-10 × 2:00 hard / 2:00 easy (fixed load)',
          'tempo': '40-55 min with 2×10-12 min surges @ RPE 6-7 (fixed load)',
          'longRuck': 'build 90 → 150-165 min; practice fueling every 30-40 min',
        },
        'targetLoadRange': '≈14-20 kg (30-45 lb), personalized',
      },
      progressionRules: {
        'loadRule': 'Only Long day may add +2 kg every 2-3 weeks if recovery green',
        'fixedLoadForIntervalstempo': true,
        'vert': '+100-150 m/wk on Tempo or Long as tolerated',
        'deload': {
          'frequency': 'every 4th week',
          'reduction': '≈-30% volume',
        },
        'keyMilestone': '10-mile simulation ≈2 weeks before event',
      },
      nonNegotiables: {
        'restBetweenHardRucks': '≥48 h',
        'noNewLoadPRsInTaper': true,
      },
      retests: {
        'tenMileSimulation': '≈2 weeks before event',
      },
      personalizationKnobs: {
        'timeBudget': true,
        'scheduledDays': true,
        'equipment': true,
        'safeStartingLoad': true,
        'terrainAccess': true,
        'intensityControl': true,
        'riskProfile': true,
        'routeWeatherSwaps': true,
        'eventSpecifics': true,
      },
    ),

    ScienceBasedPlan(
      planId: 'daily-discipline',
      name: 'Daily Discipline Streak',
      durationWeeks: 4,
      baseStructure: {
        'primaryAim': 'daily movement without overuse',
        'weeklyStructure': {
          'lightVestRecoveryWalks': '2-3 × 10-20 min @ 5-10% BW',
          'unloadedZ2': '2 × 30-45 min',
          'unloadedLong': '1 × 60-75 min',
          'optionalStrength': '30 min',
        },
        'streakSaver': 'user-set "minimum viable session" (e.g., 10-15 min unloaded)',
      },
      progressionRules: {
        'soreness': 'any soreness/hotspots → drop one vest day; substitute unloaded cardio',
        'graduation': '30 consecutive days + ≥200 Z2 min/wk, feeling fresh',
      },
      nonNegotiables: {
        'dailyMovement': true,
        'avoidOveruse': true,
        'minimumViableSession': 'counts on tough days',
      },
      retests: {
        'streakTracking': 'daily',
        'weeklyZ2Minutes': 'weekly target ≥200 min',
      },
      personalizationKnobs: {
        'timeBudget': true,
        'scheduledDays': true,
        'equipment': true,
        'safeStartingLoad': true,
        'terrainAccess': true,
        'intensityControl': true,
        'riskProfile': true,
        'routeWeatherSwaps': true,
        'minimumViableSession': true,
      },
    ),

    ScienceBasedPlan(
      planId: 'age-strong',
      name: 'Posture/Balance & Age Strong',
      durationWeeks: 8,
      baseStructure: {
        'sessionsPerWeek': {
          'lightRucks': '2-3 × 30-50 min @ 6-12% BW',
          'strengthBalance': '2 × step-ups, sit-to-stand, suitcase carries, side planks',
          'mobility': '10 min',
        },
      },
      progressionRules: {
        'carries': '+5-10 m/week or add light DBs',
        'sidePlank': '+10-15 s/week',
        'deload': {
          'week': 4,
          'reduction': 'reduce one set and ≈20-30% ruck minutes',
        },
      },
      nonNegotiables: {
        'prioritizePosture': true,
        'footComfort': true,
        'impactProgressions': 'only if appropriate',
      },
      retests: {
        'balance': 'every 2 weeks',
        'fullRetest': 'week 8 (plank total, single-leg balance, 10-rep sit-to-stand time)',
      },
      personalizationKnobs: {
        'timeBudget': true,
        'scheduledDays': true,
        'equipment': true,
        'safeStartingLoad': true,
        'terrainAccess': true,
        'intensityControl': true,
        'riskProfile': true,
        'routeWeatherSwaps': true,
      },
    ),

    ScienceBasedPlan(
      planId: 'load-capacity',
      name: 'Load Capacity Builder',
      durationWeeks: 8,
      baseStructure: {
        'whoWhy': 'time-capped users or load-specific goals; build carrying capacity safely',
        'sessionsPerWeek': {
          'rucks': '2-3',
          'unloadedCardio': '1-2',
          'shortStrength': '2 × 30-35 min (include suitcase carries)',
        },
        'ruckTypes': {
          'A_Z2Duration': '45-65 min',
          'B_LongDay': '60-120 min (fuel >90 min)',
          'C_TechniqueHills': '40-50 min easy with 100-200 m vert (optional)',
        },
        'startingLoad': {
          'percentage': '≈10-12% BW',
          'cap': 'most rec users cap near ≈20% BW for months',
        },
      },
      progressionRules: {
        'loadRule': 'Only Long day progresses load (+1-2% BW every 2-3 weeks if green). Other days hold.',
        'deload': {
          'week': 4,
          'reduction': '≈-30% time; keep load',
        },
      },
      nonNegotiables: {
        'weeklyIncreaseLimit': '≤10% weekly increase in total ruck minutes',
        'ruckFrequencyCap': '≤3/week',
        'noRuckRunning': true,
      },
      retests: {
        '60minRuck': 'week 8 at current Long-day load; compare pace/HR/RPE vs week 1',
      },
      personalizationKnobs: {
        'timeBudget': true,
        'scheduledDays': true,
        'equipment': true,
        'safeStartingLoad': true,
        'terrainAccess': true,
        'intensityControl': true,
        'riskProfile': true,
        'routeWeatherSwaps': true,
      },
    ),
  ];

  static ScienceBasedPlan? getPlanById(String planId) {
    try {
      return basePlans.firstWhere((plan) => plan.planId == planId);
    } catch (e) {
      return null;
    }
  }
}