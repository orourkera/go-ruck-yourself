class ScienceBasedPlan {
  final String planId;
  final String name;
  final int durationWeeks;
  final Map<String, dynamic> baseStructure;
  final Map<String, dynamic> personalizationKnobs;
  final Map<String, dynamic> progressionRules;
  final Map<String, dynamic> nonNegotiables;
  final Map<String, dynamic> retests;
  final Map<String, dynamic>? expertTips;

  const ScienceBasedPlan({
    required this.planId,
    required this.name,
    required this.durationWeeks,
    required this.baseStructure,
    required this.personalizationKnobs,
    required this.progressionRules,
    required this.nonNegotiables,
    required this.retests,
    this.expertTips,
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
      'expertTips': expertTips,
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
      expertTips: json['expertTips'] as Map<String, dynamic>?,
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
      expertTips: {
        'loadProgression': [
          'Only progress load on your longest ruck day',
          'Hold load constant on shorter sessions',
          '20% bodyweight is practical ceiling for most people'
        ],
        'tissueTolerance': [
          'Gradually build carrying capacity over months not weeks',
          'Suitcase carries build anti-lateral strength for rucking'
        ],
        'capacityBuilding': [
          'Time under load matters more than speed',
          'Focus on posture and gait efficiency under load'
        ]
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
      expertTips: {
        'trainingFocus': [
          'Strength + cardio combo is key for fast rucking',
          'Elite runners need strength training to become elite ruckers',
          'Strong people need more cardio volume for speed gains'
        ],
        'pacing': [
          'Always aim for negative splits (second half faster)',
          'Start conservatively, finish strong',
          'Save energy for the back half'
        ],
        'specificity': [
          'Less ruck running = better results until 3 months out',
          'Focus on running and strength training for base building',
          '1x/week ruck running maximum when event-specific'
        ]
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
      expertTips: {
        'timeline': [
          'Minimum 6 weeks prep for respectable time',
          '12+ weeks needed to go from unfit to sub-2hr',
          'Last 7-10 days should be taper (reduce volume, maintain fitness)',
          'Never cram - adaptations take weeks not days'
        ],
        'pacingStrategy': [
          'ALWAYS negative split - second 6 miles faster than first',
          'Sub-2hr target: ~9:30/mile average with negative split',
          'Start conservatively around 10:00/mile, finish around 9:00/mile',
          'Going out too fast destroys back-half performance'
        ],
        'hydrationFueling': [
          'Start hydration protocol 3-5 days before event',
          'Plain water is not enough - need electrolytes',
          'Practice fueling every 30-40min during long rucks',
          'High-carb breakfast 2+ hours before (not enough alone)',
          'Heat acclimatization must start weeks in advance'
        ],
        'performanceBenchmarks': [
          'Sub-2hr = top 10% territory',
          '1H55M-2H05M = top 5 finisher range',
          '2H20M-2H35M = above average',
          '2H35M-2H45M = average',
          'Anything under 2H45M puts you ahead of most'
        ],
        'trainingPhilosophy': [
          'Aerobic endurance + muscular endurance + full body strength',
          'Minimize ruck running volume until final months',
          'Running fitness + strength = ruck speed',
          'Overtraining is more common than undertraining'
        ]
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
      expertTips: {
        'streakPsychology': [
          'Minimum viable session still counts on tough days',
          'Perfect is the enemy of good - show up consistently',
          'Missing one day breaks streak, but don\'t let it break momentum'
        ],
        'recoveryFocus': [
          'This plan prioritizes recovery and tissue health',
          'Light load prevents overuse while building habit',
          'Any soreness = immediate plan adjustment'
        ],
        'habitFormation': [
          'Daily movement creates neural pathways for long-term success',
          'Start ridiculously small to ensure early wins',
          '30 days builds automatic behavior patterns'
        ]
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
      expertTips: {
        'longevityFocus': [
          'Light loads prevent joint wear while building strength',
          'Functional movements translate to daily life',
          'Balance training prevents falls and injuries'
        ],
        'progressionMindset': [
          'Small consistent gains compound over time',
          'Quality movement patterns over quantity',
          'Listen to your body - pain is not gain at this stage'
        ],
        'foundationBuilding': [
          'Master bodyweight before adding load',
          'Stability before mobility, mobility before strength',
          'Posture improvements take 6-8 weeks to feel natural'
        ]
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
      expertTips: {
        'loadProgression': [
          'Only progress load on your longest ruck day',
          'Hold load constant on shorter sessions',
          '20% bodyweight is practical ceiling for most people'
        ],
        'tissueTolerance': [
          'Gradually build carrying capacity over months not weeks',
          'Suitcase carries build anti-lateral strength for rucking'
        ],
        'capacityBuilding': [
          'Time under load matters more than speed',
          'Focus on posture and gait efficiency under load'
        ]
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