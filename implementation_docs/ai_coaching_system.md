# AI Coaching System - Implementation Guide

## Overview
This document outlines the comprehensive AI coaching system for the Ruck! app, designed to provide personalized, adaptive coaching that goes beyond simple plan execution to create a true coaching relationship with users.

## Core Philosophy
Think **Netflix recommendations, not gym class curriculum**. The AI should learn user preferences, adapt to their reality, and create a personalized coaching experience that becomes more valuable over time.

---

## User Flow Architecture

### Initial User Journey
1. **Goal Selection Screen**
   - Present different goal types (weight loss, endurance, military prep, general fitness)
   - Show preview of what each plan entails
   - Allow users to see time commitment and progression overview

2. **Plan Preview & Commitment**
   - Detailed view of selected goal plan
   - Timeline visualization (4-week, 8-week, 12-week options)
   - "Yes, coach me through this plan" commitment action
   - Set coaching personality preference

3. **Progress Dashboard**
   - Visual progress indicator showing plan adherence
   - Weekly/monthly view of planned vs. actual sessions
   - Milestone tracking with context

### Active Plan Experience
- **Homepage AI Insights**: Plan-contextual updates and next steps
- **Smart Notifications**: Proactive coaching based on behavior patterns
- **Session Creation**: Plan-aware recommendations with guardrails
- **AI Cheerleader**: Plan-reinforced motivation during sessions
- **Post-Session Analysis**: Achievement assessment and next steps

---

## Core Features

### ✅ Current Implementation (Strong Foundation)
- **Goal-Driven Onboarding**: Clear goal → plan → commitment flow
- **Visual Progress Tracking**: User can see adherence to plan
- **Contextual AI Integration**: Homepage insights, session coaching, post-session feedback
- **Smart Guardrails**: Overtraining prevention, recovery guidance
- **Plan Flexibility**: User can cancel/adjust plans as needed

### 🚀 Enhanced Features (Implementation Needed)

#### 1. Dynamic Plan Adaptation
```
Current: Static plan with compliance tracking
Enhanced: Adaptive plan that learns and evolves

Examples:
- "Your last 3 rucks were shorter than planned. Should we adjust your distance targets?"
- "You've been crushing your goals! Ready to level up the plan?"
- Seasonal adjustments (winter alternatives, summer heat considerations)
- Performance-based modifications
```

#### 2. Advanced Motivation Psychology
```
Current: Basic progress tracking + notifications
Enhanced: Behavioral change science integration

Features:
- Streak protection ("2 days from your longest streak!")
- Identity reinforcement ("You're becoming a consistent rucker")
- Social proof ("85% of users at this stage complete their plan")
- Micro-celebrations (not just major milestones)
- Habit formation optimization (cue-routine-reward loops)
```

#### 3. Structured Plan Flexibility
```
Current: Simple cancel/adjust options
Enhanced: Intelligent flexibility framework

Options:
- Maintenance mode (reduced intensity for busy periods)
- Injury recovery modifications
- Travel-friendly alternatives
- Schedule conflict resolution ("Swap Tuesday for Saturday this week")
- Weather-based adaptations
```

#### 4. Off-Ramps & Life Flexibility System
```
Travel/Vacation Mode:
- Automatically switches to bodyweight or light load sessions
- Step-count targets when rucking isn't possible
- Hotel room/airport alternatives
- Auto-resume plan upon return with recalibrated progression

Sick/Injury Mode:
- Immediate plan pause with no penalty to progress
- Gentle return-to-load ladder based on time away
- Medical clearance prompts for longer absences
- Modified movement patterns during recovery

Plan Evolution Without History Loss:
- Edit plan length (extend 8-week to 12-week) while preserving progress
- Goal swapping with intelligent progress translation
- Seasonal plan modifications (winter indoor focus)
- Life stage adaptations (new parent mode, busy season adjustments)
```

#### 4. Failure Recovery System
```
Current: Notifications when behind schedule
Enhanced: Comprehensive comeback pathways

Features:
- "Missed a week? Here's your comeback plan"
- "Behind schedule? 3 options to get back on track"
- Guilt-free restart mechanisms
- Progress preservation ("Your fitness isn't lost - pick up here")
- Graduated re-entry options
```

---

## Behavioral Change Science Integration

### Habit Formation Loop Implementation
```
Cue → Routine → Reward → Tracking

Cue Optimization:
- "Best time for rucks: 7am (based on your completion rate)"
- Calendar integration for automatic reminders
- Weather-based timing suggestions

Routine Stacking:
- "Pair rucks with existing dog walks?"
- Integration with user's existing habits
- Location-based routine suggestions

Reward Amplification:
- Achievement celebrations with context
- Progress milestones with meaning
- External reward integration (discounts, etc.)
```

### Progressive Disclosure of Complexity
```
Week 1-2: Focus on consistency only
Week 3-4: Introduce basic metrics awareness
Week 5-8: Add pace/heart rate optimization  
Week 9+: Advanced training periodization

Goal: Don't overwhelm beginners with everything at once
```

---

## Off-Ramps & Life Flexibility - Detailed Implementation

### Travel/Vacation Mode
```
Activation Triggers:
- User manually enables "Travel Mode"
- Calendar integration detects travel events
- Location changes detected (optional)

Adaptive Features:
- Bodyweight-only session alternatives
- Hotel room workouts (15-20 minute versions)
- Airport/airplane movement suggestions
- Step count targets when sessions aren't possible (8k-12k steps)
- Walking tour suggestions in destination cities

Example Flow:
"I see you're traveling to Denver next week. Switch to Travel Mode?
- 3 bodyweight sessions (hotel room friendly)  
- Daily 10k step targets
- Optional: Denver hiking trail suggestions for loaded carries
Auto-resume your regular plan when you return Friday."

Return Recalibration:
- Assess fitness retention based on time away and activity level
- Gradual re-introduction of load (start 80% of previous weight)
- Extended warm-up periods for first 2-3 sessions back
```

### Sick/Injury Mode
```
Immediate Pause Features:
- One-tap plan suspension with no progress penalty
- "Sick day" vs "Injury" classification for different recovery paths
- Progress preservation ("You haven't lost your streak - just paused it")

Return-to-Activity Protocols:
Time Away: 3-7 days (illness)
- Resume at 80% previous intensity
- Monitor RPE more closely for first week
- Extended warm-up recommendations

Time Away: 1-4 weeks (injury/major illness)
- Medical clearance prompt for longer absences
- Progressive return ladder:
  - Week 1: Bodyweight walking only
  - Week 2: Light load (50% previous weight)
  - Week 3: Moderate load (75% previous weight)  
  - Week 4: Full return if all markers positive

Smart Recovery Monitoring:
- RPE tracking during return phase
- Sleep and energy level check-ins
- Pain/discomfort assessments
- Automatic progression holds if recovery indicators are poor
```

### Plan Evolution System
```
Length Adjustments Without History Loss:
- "Extend 8-week plan to 12 weeks" - redistributes milestones
- "Compress 12-week to 8 weeks" - accelerates progression (with safety checks)
- "Add maintenance phase" - extends current level without progression

Goal Translation Matrix:
Weight Loss → Endurance:
- Preserve weekly frequency habits
- Translate calorie burn focus to distance/pace focus
- Maintain load progression but shift emphasis

Military Prep → General Fitness:
- Reduce intensity requirements
- Maintain strength/endurance base
- Remove military-specific components

Endurance → Weight Loss:
- Maintain aerobic base
- Add metabolic focus sessions
- Introduce calorie burn optimization

Seasonal Adaptations:
Summer → Winter:
- Shift outdoor long sessions to indoor interval work
- Add indoor alternatives for weather-dependent sessions
- Adjust hydration and heat management protocols

Winter → Spring:
- Gradually increase outdoor exposure
- Rebuild heat tolerance protocols
- Seasonal allergy considerations

Life Stage Modifications:
New Parent Mode:
- Shorter session options (20-30 minute alternatives)
- Home-based alternatives for unpredictable schedules
- Sleep deprivation adaptations (lower intensity targets)

Busy Season (Work):
- Micro-session options (10-15 minute active recovery)
- Early morning or late evening optimized sessions
- Weekend warrior modifications
```

### Implementation UX Flow
```
Plan Modification Interface:
Settings → My Plan → Modify Plan

Options Presented:
□ Change plan length (8 → 12 weeks)
□ Switch goal type (Weight Loss → Endurance)
□ Enable Travel Mode (dates: ___ to ___)
□ Enable Sick/Recovery Mode
□ Seasonal adjustment (Winter adaptations)
□ Life situation change (New parent, busy period)

Each option shows:
- Preview of changes
- Impact on current progress
- Timeline adjustment
- "This won't affect your streak or progress history"

Confirmation Flow:
"Switching from Weight Loss to Endurance will:
✓ Keep your 15-day consistency streak
✓ Maintain your current fitness level
✓ Adjust future sessions to focus on distance/pace
✓ Preserve all your completed sessions

Your new plan starts tomorrow. Ready to make the switch?"
```

---

## Enhanced User Experience Design

### Homepage AI Insights (Enhanced)
```
Instead of: "You're on track with your plan"

Enhanced: "Day 12 of 28: You're ahead of schedule! Tomorrow's ruck: 
          2.5 miles at conversational pace. Weather looks perfect 🌤️
          
          Your consistency is building - 7 rucks in 10 days. At this 
          rate, you'll finish 3 days early. Want to add a challenge?"
```

### Smart Notifications (Enhanced)
```
Instead of: "You missed your ruck"

Enhanced: "I know Wednesdays are tough. Want to move today's ruck to 
          tomorrow, or try a quick 15-minute evening walk instead?
          
          Your schedule shows you're free Thursday at 6pm - perfect 
          for a makeup session."
```

### Session Creation Intelligence (Enhanced)
```
Current: Basic weight/distance guardrails

Enhanced: "Based on your plan and recent performance, I recommend:
          - 2.2 miles (your sweet spot distance)
          - 20lbs (you seemed strong last ruck)  
          - Route suggestion: Park loop (recovery-friendly terrain)
          - Weather note: 15% chance rain at 7am, clear by 8am"
```

---

## Coaching Personality System

### Personality Options
Users select their preferred coaching style during onboarding:

#### 1. Drill Sergeant
- **Tone**: Direct, challenging, no-nonsense
- **Example**: "Drop and give me 20! No excuses today - you committed to this plan!"
- **Best for**: Users who respond to tough love and accountability

#### 2. Supportive Friend  
- **Tone**: Encouraging, empathetic, understanding
- **Example**: "You've got this! Remember why you started - every step matters."
- **Best for**: Users who need emotional support and gentle motivation

#### 3. Data Nerd
- **Tone**: Analytical, metrics-focused, optimization-oriented
- **Example**: "Your pace improved 12% this week based on heart rate zones. Let's dial in your Zone 2 training."
- **Best for**: Users motivated by numbers and performance metrics

#### 4. Minimalist
- **Tone**: Brief, actionable, efficient
- **Example**: "2.5 miles. 20 lbs. Go."
- **Best for**: Users who want guidance without lengthy explanations

---

## Supported Coaching Plans

### 1. Fat Loss & Feel Better
```
Description: Build a steady calorie deficit and improve everyday energy with low-impact, progressive rucking plus complementary cardio/strength. We keep it safe, sustainable, and data-driven—no crash tactics.

Success Metrics:
- Consistent weekly calorie burn through rucking
- Downward weight/waist trend over plan duration
- Better day-to-day energy levels and recovery

Tracking Elements:
- Weekly ruck calories burned
- Body mass trend (weight tracking)
- Resting heart rate (optional)
- Energy level assessments
- Weekly ruck frequency and duration

Plan Structure (12 weeks):
Week 1-4: Base building (3x/week, bodyweight, focus on consistency)
Week 5-8: Calorie optimization (add light load, extend time)
Week 9-12: Metabolic focus (interval work, terrain variation)
```

### 2. Get Faster at Rucking
```
Description: Improve your 60-minute ruck pace at a fixed load using aerobic base, controlled tempo work, and smart hills—without trashing your legs.

Success Metrics:
- Faster pace at same load (or same pace at lower heart rate)
- Smoother effort distribution across the hour
- Improved aerobic efficiency

Tracking Elements:
- 60-minute pace at fixed load
- Heart rate drift during Zone 2 sessions (Apple Watch integration only)
- RPE consistency across sessions
- Lactate threshold improvements (Apple Watch integration only)
- Recovery between sessions

Plan Structure (10 weeks):
Week 1-3: Aerobic base building (Zone 2 focus)
Week 4-6: Tempo integration (controlled faster efforts)
Week 7-9: Hill work and power (smart elevation training)
Week 10: Testing and consolidation
```

### 3. 12-Mile Under 3:00 (Custom Event Prep)
```
Description: Arrive prepared for your event with focused quality sessions, a long-ruck progression, and a taper that respects your feet and recovery.

Success Metrics:
- Complete target distance under time goal
- Maintain stable form and minimal hotspots
- Steady heart rate in final third of event
- Proper fueling and hydration execution

Tracking Elements:
- Long-day pace vs. target pace
- Load carried during training
- Foot/skin condition checks
- Fueling adherence and tolerance
- Weekly peak distance progression
- Recovery markers

Plan Structure (16 weeks):
Week 1-6: Base building and load adaptation
Week 7-12: Long ruck progression and speed work
Week 13-15: Peak preparation and dress rehearsals
Week 16: Taper and event execution
```

### 4. Daily Discipline Streak
```
Description: Build an unbreakable habit with bite-size sessions, flexible scheduling, and gentle accountability—movement every day, without overuse.

Success Metrics:
- Achieve and maintain 30+ day completion streak
- Meet weekly Zone 2 minute targets (Apple Watch integration only)
- Feel fresh and energized (not overtrained)
- Build sustainable daily movement habits

Tracking Elements:
- Daily streak counter
- Weekly time-in-Zone 2 (Apple Watch integration only)
- Soreness/readiness flags
- Session flexibility and adaptation
- Habit strength indicators

Plan Structure (8 weeks):
Week 1-2: Habit establishment (short, easy sessions)
Week 3-4: Routine solidification (consistent timing)
Week 5-6: Quality improvement (Zone 2 targets - Apple Watch users only)
Week 7-8: Streak protection and sustainability
```

### 5. Posture/Balance & Age-Strong
```
Description: Move taller and steadier with light loaded walks plus simple balance/strength work that supports joints and confidence.

Success Metrics:
- Longer stable single-leg stance times
- Stronger carrying capacity for daily activities
- Easier navigation of stairs and ADLs
- Improved postural awareness and control

Tracking Elements:
- Plank and side-plank hold times
- Single-leg balance duration
- Sit-to-stand time
- Loaded carry distances
- Daily function assessments

Plan Structure (12 weeks):
Week 1-4: Foundation (light loads, basic balance work)
Week 5-8: Progressive loading (increase carry weight/time)
Week 9-12: Functional integration (real-world applications)
```

### 6. Load Capacity Builder
```
Subtitle: "Build how much you can carry—safely and steadily."

Description: Safely increase how much weight you can carry. We progress one knob at a time (time → hills → small load bumps) with readiness checks so feet, knees, and back adapt without flare-ups. Best for time-capped users or load-specific events.

Success Metrics:
- Complete same routes at higher % body weight
- Maintain steady pace and stable HR/RPE
- No next-day joint/foot pain or issues
- Progressive load tolerance improvement

Tracking Elements:
- Long-day load (kg & % body weight)
- 60-minute pace at current load
- Heart rate drift during sessions (Apple Watch integration only)
- Rate of Perceived Exertion
- Next-day joint/foot status checks
- Weekly ruck minutes and load progression

Plan Structure (14 weeks):
Week 1-4: Time adaptation (extend duration at current load)
Week 5-8: Terrain progression (add hills at current load)
Week 9-12: Load increases (small weight bumps with monitoring)
Week 13-14: Consolidation and testing
```

### Plan Template Framework
```
Each plan includes:
- Detailed weekly progression structure
- Branching logic for different user responses
- Success criteria and failure recovery paths
- Specific tracking metrics and assessments
- Personality-adapted coaching language
- Off-ramp integration for life flexibility
- Achievement milestones and celebrations

Note on Heart Rate/Zone 2 Tracking:
- All Zone 2, heart rate drift, and lactate threshold tracking features require Apple Watch integration
- Plans automatically adapt for users without Apple Watch by focusing on RPE, pace, and time-based metrics
- Non-Apple Watch users receive equivalent training benefits through alternative tracking methods
```

---

## Community Integration Features

### Social Coaching Elements
```
Plan Buddies:
- "3 other users in your area are doing this same plan"
- Progress comparisons (opt-in)
- Shared milestone celebrations

Group Challenges:
- "Join the Week 6 Challenge group chat"
- Plan-specific community groups
- Peer accountability features

Success Stories:
- "Sarah just completed this plan - here's her advice"
- User testimonials and tips
- Graduated user mentorship
```

---

## Page Integration & Implementation

### Achievements Page - Plan Creation Integration
```
Current State:
- Achievements page contains "Create Goal" functionality
- Users can set basic goals and track progress

Enhanced Integration for AI Coaching:
- Repurpose existing "Create Goal" as "Create Coaching Plan"
- Maintain goal creation but add comprehensive plan selection
- Leverage existing UI patterns for consistency
```

### Implementation Strategy
```
Phase 1: Enhance Existing Goal Creation
Current: Basic goal setting
Enhanced: AI coaching plan selection

UI Flow on Achievements Page:
1. "Create Goal" button → "Create Coaching Plan"
2. Goal type selection (existing functionality)
3. NEW: Plan preview and commitment flow
4. NEW: Coaching personality selection
5. Existing: Goal creation confirmation

Benefits of Using Achievements Page:
- Users already associate this page with goal-setting
- Existing UI patterns reduce development time
- Natural progression from achievements → new goals → plans
- Maintains navigation familiarity
```

### Detailed Implementation Plan
```
Achievements Page Modifications:

1. Update "Create Goal" Button:
   - Change text to "Start AI Coaching Plan"
   - Add coaching icon/indicator
   - Maintain existing button styling

2. Enhanced Goal Selection Flow:
   Existing Flow: Goal Type → Goal Details → Create
   New Flow: Goal Type → Plan Preview → Coaching Setup → Create Plan

3. Plan Preview Integration:
   - Show plan timeline (4/8/12 week options)
   - Display weekly structure and progression
   - Include difficulty and time commitment indicators
   - "Yes, coach me through this plan" commitment action

4. Coaching Personality Selection:
   - Add coaching style selection after plan preview
   - 4 personality types with descriptions
   - Default selection based on goal type

5. Progress Integration:
   - Existing achievement tracking remains
   - NEW: Plan-specific progress indicators
   - Achievement unlocks tied to plan milestones
   - Dual tracking: goals + coaching plan progress
```

### UI Component Reuse Strategy
```
Leverage Existing Components:
- Goal type cards (adapt for plan types)
- Progress indicators (enhance for plan tracking)
- Achievement badges (add plan milestone badges)
- Timeline visualization (extend for plan duration)

New Components Needed:
- Plan preview cards with timeline
- Coaching personality selector
- Plan progress dashboard widget
- Plan modification interface

Navigation Integration:
- Achievements → Create Plan (existing button)
- Achievements → View Active Plan (new section)
- Homepage → Plan Progress (link to achievements)
- Settings → Modify Plan (new option)
```

### Data Model Extensions
```
Existing Achievement Data:
- Goal types, target values, completion tracking
- User progress history
- Achievement unlock system

New Plan Data Requirements:
- Plan templates (goal type → plan structure)
- Plan instance (user's active plan + progress)
- Coaching personality preference
- Plan modifications history
- Off-ramp activations (travel mode, sick mode, etc.)

Database Schema Additions:
- coaching_plans table (plan templates)
- user_coaching_plans table (active user plans)  
- plan_modifications table (history of changes)
- plan_sessions table (plan-specific session tracking)
```

### Achievements Page Layout Enhancement
```
Current Layout:
[Header]
[Achievement Grid]
[Create Goal Button]
[Progress Stats]

Enhanced Layout:
[Header]
[Active Plan Progress Widget] ← NEW
[Achievement Grid] (filtered by plan if active)
[Create Coaching Plan Button] ← ENHANCED
[Plan + Achievement Stats] ← ENHANCED

Active Plan Progress Widget:
- Current plan name and week progress
- Next session recommendation
- Quick plan modification options
- Progress streak indicator

Benefits:
- Single page for all goal-related activities
- Reduced navigation complexity
- Contextual achievement display based on active plan
- Consistent user mental model (achievements = goals = plans)
```

### Implementation Phases
```
Phase 1: Basic Integration
- [ ] Update "Create Goal" to "Create Coaching Plan"
- [ ] Add plan preview step to existing goal flow
- [ ] Basic plan templates (3-4 goal types)
- [ ] Simple coaching personality selection
- [ ] Plan progress widget on achievements page

Phase 2: Enhanced Features
- [ ] Advanced plan templates with branching logic
- [ ] Plan modification interface from achievements page
- [ ] Achievement integration with plan milestones
- [ ] Off-ramp activation from achievements page

Phase 3: Full AI Integration  
- [ ] Dynamic plan adaptation based on progress
- [ ] AI-driven achievement recommendations
- [ ] Personalized plan suggestions on achievements page
- [ ] Community features integration

Migration Strategy:
- Existing goals convert to "legacy goals" 
- Users prompted to upgrade to coaching plans
- Maintain backward compatibility
- Gradual feature rollout to prevent confusion
```

---

## Detailed Implementation Plan

### Phase 1: Create Goal Page Enhancement (Start Here)

#### Flutter App Modifications

##### 1. Create Goal Page UI Updates
```
Files to Modify:
- /lib/features/achievements/presentation/screens/achievements_screen.dart
- /lib/features/achievements/presentation/widgets/create_goal_widget.dart (if exists)
- /lib/features/achievements/domain/models/goal.dart

Changes Required:
1. Update "Create Goal" button text to "Start AI Coaching Plan"
2. Add coaching plan selection flow after goal type selection
3. Create new coaching plan preview cards
4. Add coaching personality selection screen
5. Integrate plan commitment confirmation flow

New Components to Create:
- /lib/features/coaching/presentation/widgets/plan_preview_card.dart
- /lib/features/coaching/presentation/widgets/coaching_personality_selector.dart  
- /lib/features/coaching/presentation/screens/plan_creation_flow_screen.dart
- /lib/features/coaching/presentation/widgets/plan_commitment_dialog.dart
```

##### 2. Navigation Flow Enhancement
```
Current Flow:
Achievements Screen → Create Goal → Goal Type Selection → Goal Creation

New Flow: 
Achievements Screen → Start AI Coaching Plan → Goal Type Selection → 
Plan Preview → Coaching Personality → Plan Commitment → Plan Creation

Files to Modify:
- /lib/core/navigation/app_router.dart
- /lib/features/achievements/presentation/bloc/achievements_bloc.dart

New Routes to Add:
- /coaching/plan-preview/:goalType
- /coaching/personality-selection
- /coaching/plan-commitment
```

##### 3. Domain Models Extension
```
New Models to Create:
- /lib/features/coaching/domain/models/coaching_plan.dart
- /lib/features/coaching/domain/models/coaching_personality.dart
- /lib/features/coaching/domain/models/plan_session.dart
- /lib/features/coaching/domain/models/plan_progress.dart

Existing Models to Extend:
- /lib/features/achievements/domain/models/goal.dart
  - Add coaching_plan_id field
  - Add is_coaching_plan boolean
  - Add plan_start_date field
```

##### 4. State Management (BLoC)
```
New BLoCs to Create:
- /lib/features/coaching/presentation/bloc/coaching_plan_bloc.dart
- /lib/features/coaching/presentation/bloc/plan_creation_bloc.dart

Events:
- PlanTypeSelected
- PersonalitySelected  
- PlanCommitted
- PlanProgressRequested
- PlanModificationRequested

States:
- PlanCreationInitial
- PlanPreviewLoaded
- PersonalitySelectionRequired
- PlanCommitmentPending
- PlanCreated
- PlanCreationError
```

#### Backend (Python) Modifications

##### 1. Database Schema Additions
```
New Tables to Create in migrations/:

1. coaching_plans (plan templates)
CREATE TABLE coaching_plans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    goal_type VARCHAR(100) NOT NULL,
    description TEXT,
    duration_weeks INTEGER NOT NULL,
    plan_structure JSONB NOT NULL,
    success_metrics JSONB,
    tracking_elements JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

2. user_coaching_plans (active user plans)  
CREATE TABLE user_coaching_plans (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    coaching_plan_id INTEGER REFERENCES coaching_plans(id),
    coaching_personality VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    target_end_date DATE NOT NULL,
    current_week INTEGER DEFAULT 1,
    status VARCHAR(50) DEFAULT 'active',
    plan_modifications JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

3. plan_sessions (plan-specific session tracking)
CREATE TABLE plan_sessions (
    id SERIAL PRIMARY KEY,
    user_coaching_plan_id INTEGER REFERENCES user_coaching_plans(id),
    session_id UUID REFERENCES sessions(id),
    planned_week INTEGER,
    planned_session_type VARCHAR(100),
    completion_status VARCHAR(50),
    plan_adherence_score DECIMAL(3,2),
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

4. plan_modifications (history of plan changes)
CREATE TABLE plan_modifications (
    id SERIAL PRIMARY KEY,
    user_coaching_plan_id INTEGER REFERENCES user_coaching_plans(id),
    modification_type VARCHAR(100) NOT NULL,
    from_value JSONB,
    to_value JSONB,
    reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);
```

##### 2. New Python API Files
```
Files to Create:

1. /api/coaching_plans.py
- GET /api/coaching-plans - List available plan templates
- GET /api/coaching-plans/:id - Get specific plan details
- POST /api/user-coaching-plans - Create new user plan
- GET /api/user-coaching-plans/:user_id - Get user's active plans
- PUT /api/user-coaching-plans/:id - Modify existing plan
- DELETE /api/user-coaching-plans/:id - Cancel/archive plan

2. /services/coaching_service.py
- Plan template management
- Plan progression logic
- Plan adaptation algorithms
- Progress calculation methods
- Plan recommendation engine

3. /services/plan_progress_service.py
- Weekly progress calculation
- Adherence scoring algorithms
- Next session recommendations
- Plan modification suggestions
- Off-ramp trigger detection
```

##### 3. Existing Files to Modify
```
Files to Update:

1. /app.py
- Add new coaching plan routes
- Register coaching blueprints

2. /api/achievements.py
- Integrate coaching plans with achievement system
- Add plan-specific achievement triggers
- Link goal creation with plan creation

3. /api/sessions.py
- Add plan context to session completion
- Include plan adherence scoring
- Trigger plan progress updates

4. /services/ai_insights_service.py
- Include plan progress in insights generation
- Add plan-specific coaching recommendations
- Integrate plan status with homepage insights
```

#### Database Seed Data
```
Initial Plan Templates to Add:

1. Fat Loss & Feel Better (12 weeks)
2. Get Faster at Rucking (10 weeks)  
3. 12-Mile Under 3:00 (16 weeks)
4. Daily Discipline Streak (8 weeks)
5. Posture/Balance & Age-Strong (12 weeks)
6. Load Capacity Builder (14 weeks)

Coaching Personalities:
1. Drill Sergeant
2. Supportive Friend
3. Data Nerd
4. Minimalist

Migration File:
/migrations/xxxx_add_coaching_system_tables.sql
/migrations/xxxx_seed_coaching_plans.sql
```

### Phase 2: Plan Progress Integration

#### Flutter App Enhancements
```
Files to Create/Modify:

1. Homepage AI Insights Integration
- /lib/features/home/presentation/widgets/ai_insights_widget.dart
  - Add plan progress context to insights
  - Include next session recommendations
  - Display plan adherence status

2. Achievements Page Enhancement  
- /lib/features/achievements/presentation/screens/achievements_screen.dart
  - Add active plan progress widget
  - Filter achievements by active plan
  - Add plan modification options

3. Session Creation Integration
- /lib/features/ruck_session/presentation/screens/create_session_screen.dart
  - Add plan-recommended session settings
  - Include plan adherence warnings
  - Show plan context for current session

4. New Plan Management Screens
- /lib/features/coaching/presentation/screens/plan_overview_screen.dart
- /lib/features/coaching/presentation/screens/plan_modification_screen.dart
- /lib/features/coaching/presentation/widgets/plan_progress_widget.dart
```

#### Backend Enhancements
```
Files to Create/Modify:

1. Plan Progress API
- /api/plan_progress.py
  - GET /api/plan-progress/:user_id - Current progress
  - POST /api/plan-progress/session-complete - Update after session
  - GET /api/plan-recommendations/:user_id - Next session suggestions

2. Enhanced Services
- /services/plan_adaptation_service.py
  - Dynamic plan adjustments based on performance
  - Off-ramp activation logic
  - Plan difficulty scaling

3. AI Integration
- /services/ai_coaching_service.py
  - Plan-aware coaching personalities
  - Session-specific coaching prompts
  - Progress-based motivation generation
```

### Phase 3: Advanced Features

#### Off-Ramps & Flexibility
```
Flutter Components:
- /lib/features/coaching/presentation/screens/plan_modification_screen.dart
- /lib/features/coaching/presentation/widgets/off_ramp_selector.dart
- /lib/features/coaching/presentation/widgets/travel_mode_config.dart

Backend Services:
- /services/off_ramp_service.py
- /services/plan_flexibility_service.py

Database Extensions:
- off_ramp_activations table
- plan_pauses table
```

#### Community Integration
```
Flutter Components:
- /lib/features/coaching/presentation/screens/plan_community_screen.dart
- /lib/features/coaching/presentation/widgets/plan_buddy_widget.dart

Backend Services:
- /services/coaching_community_service.py
- /api/coaching_community.py
```

### Implementation Priority Order

#### Week 1-2: Foundation
- [ ] Database schema creation and migrations
- [ ] Basic plan template seeding
- [ ] Core domain models in Flutter
- [ ] Basic API endpoints for plan CRUD

#### Week 3-4: Create Goal Enhancement  
- [ ] Update achievements page UI for plan creation
- [ ] Implement plan preview flow
- [ ] Add coaching personality selection
- [ ] Create plan commitment confirmation

#### Week 5-6: Progress Integration
- [ ] Homepage AI insights plan integration
- [ ] Session creation plan recommendations  
- [ ] Basic progress tracking and display
- [ ] Plan adherence scoring

#### Week 7-8: Plan Management
- [ ] Plan overview and modification screens
- [ ] Off-ramp implementation (travel/sick modes)
- [ ] Plan adaptation algorithms
- [ ] Advanced progress visualization

#### Week 9-10: Polish & Testing
- [ ] UI/UX refinements
- [ ] Performance optimization
- [ ] Integration testing
- [ ] User acceptance testing

---

## Technical Implementation Considerations

### Plan Progress Visualization
- **Weekly Grid View**: Planned vs actual sessions with color coding
- **Trend Analysis**: "Building consistency - 7 rucks in 10 days"
- **Milestone Celebrations**: Contextual achievements with meaning
- **Adjustment Tracking**: History of plan modifications and reasons

### Data Integration Points
```
Required Data Sources:
- Session completion data
- User preferences and feedback
- Weather data for recommendations
- Calendar integration for scheduling
- Sleep/stress data (if available)
- Heart rate and performance metrics

AI Learning Inputs:
- Completion patterns by day/time
- Preferred session lengths
- Response to different coaching styles  
- Plan modification history
- Success/failure patterns
```

### Recovery & Life Integration
```
Holistic Coaching Features:
- Sleep impact tracking ("Rucks are 15% slower with <7hrs sleep")
- Stress level check-ins and plan adjustments
- Calendar integration for automatic plan modifications
- Life event accommodations (travel, illness, major life changes)
- Cross-training recommendations
```

---

## Implementation Phases

### Phase 1: Foundation (MVP)
- [ ] Basic plan templates (3-4 goal types)
- [ ] Progress tracking dashboard
- [ ] Plan-aware homepage insights
- [ ] Session recommendations based on plan
- [ ] Simple plan modification options

### Phase 2: Personalization
- [ ] Coaching personality selection
- [ ] Dynamic plan adaptation based on performance
- [ ] Advanced notification intelligence
- [ ] Failure recovery pathways
- [ ] Community features (basic)

### Phase 3: Intelligence
- [ ] Machine learning for plan optimization
- [ ] Predictive coaching (injury prevention, plateau detection)
- [ ] Advanced community features
- [ ] Integration with external data sources
- [ ] Cross-platform coaching consistency

### Phase 4: Mastery
- [ ] Fully adaptive AI coaching
- [ ] Predictive health insights
- [ ] Social coaching networks
- [ ] Professional coach integration
- [ ] Long-term health outcome tracking

---

## Success Metrics

### User Engagement
- Plan completion rates by goal type
- Session consistency during active plans
- User retention through plan duration
- Plan restart/modification patterns

### Coaching Effectiveness  
- User satisfaction with coaching personality
- Response rates to AI recommendations
- Improvement in user performance metrics
- Reduction in plan abandonment

### Behavioral Change
- Habit formation success (21-day+ streaks)
- Long-term engagement post-plan completion
- User progression to advanced plans
- Community engagement levels

---

## Key Principles for Implementation

### 1. Coaching Relationship Over Plan Execution
- Focus on building trust and understanding
- Learn user preferences and adapt accordingly
- Provide value beyond just task management

### 2. Behavioral Change Science
- Apply proven psychology principles
- Design for habit formation, not just goal achievement
- Create sustainable long-term behaviors

### 3. Intelligent Flexibility
- Plans should bend, not break
- Provide structured ways to handle life's interruptions
- Maintain progress momentum even during setbacks

### 4. Progressive Enhancement
- Start simple, add complexity gradually
- Don't overwhelm users with advanced features initially
- Build confidence through early wins

### 5. Community-Driven Growth
- Leverage user success stories
- Create peer accountability mechanisms
- Build tribal identity around consistent rucking

---

## Conclusion

This AI coaching system transforms the Ruck! app from a session tracker into a comprehensive fitness coach that understands, adapts, and grows with each user. The key is creating a system that feels personal, intelligent, and genuinely helpful - not just a sophisticated to-do list.

The implementation should focus on building the foundational elements first, then gradually adding intelligence and personalization features that make the coaching experience more valuable over time.


# SOURCES.md
_Last updated: 2025-08-31_

This document lists the primary sources that inform the app’s goal templates, safety guardrails, and coaching logic. Each item includes a one‑line note on how it supports a specific product decision.

---

## 1) Activity Volume & Intensity (weekly minutes, Zone 2 ranges)

- **Physical Activity Guidelines for Americans, 2nd ed.**  
  https://health.gov/sites/default/files/2019-09/Physical_Activity_Guidelines_2nd_edition.pdf  
  _Why it matters:_ Establishes the scaffold of **150–300 min/week of moderate** aerobic activity (or 75–150 min vigorous) used in all plans.

- **ODPHP landing page for the same guidelines**  
  https://odphp.health.gov/healthypeople/tools-action/browse-evidence-based-resources/physical-activity-guidelines-americans-2nd-edition  
  _Why it matters:_ Canonical government reference page to surface inside the app’s “Why this?” tooltips.

- **ACSM Position Stand — Quantity and Quality of Exercise for Developing and Maintaining Cardiorespiratory, Musculoskeletal, and Neuromotor Fitness** (moderate ≈ **40–59% HRR**)  
  https://pubmed.ncbi.nlm.nih.gov/21694556/  
  _Why it matters:_ Defines the **Zone 2 band** (via %HRR) used in ruck/cross‑cardio intensity prescriptions.

- **American Heart Association — adult activity recommendations**  
  https://www.heart.org/en/healthy-living/fitness/fitness-basics/aha-recs-for-physical-activity-in-adults  
  _Why it matters:_ Public‑facing summary consistent with the 150/75 guidance; useful for consumer copy.

---

## 2) Load‑Carriage Energetics (why we prefer duration/grade/terrain before heavier loads)

- **LCDA graded walking equation** (handles level, uphill, and **downhill**)  
  https://pubmed.ncbi.nlm.nih.gov/30973477/  
  _Why it matters:_ Baseline metabolic rate model for walking with slope; underpins calorie estimates and coaching tradeoffs (time vs. grade).

- **LCDA — Metabolic Costs of Standing and Walking (model development)**  
  https://pubmed.ncbi.nlm.nih.gov/30649093/  
  _Why it matters:_ Core methodology behind modern USARIEM energy‑cost models used as our calorie engine basis.

- **LCDA backpacking equation (modern heavy rucks; validation vs older models)**  
  https://pmc.ncbi.nlm.nih.gov/articles/PMC8919998/  
  https://pubmed.ncbi.nlm.nih.gov/34856578/  
  _Why it matters:_ Shows improved accuracy over legacy formulas (e.g., Pandolf) for heavy loads/real terrain; justifies using LCDA in‑app.

- **Weighted‑vest walking energetics (LCDA update)**  
  https://pubmed.ncbi.nlm.nih.gov/38291646/  
  (author PDF) https://www.researchgate.net/profile/David-Looney-3/publication/377843582_Metabolic_Costs_of_Walking_with_Weighted_Vests/links/66449ee67091b94e932bfa11/Metabolic-Costs-of-Walking-with-Weighted-Vests.pdf  
  _Why it matters:_ Adds a vest‑specific term; supports handling **vest vs. backpack** loads distinctly in calorie estimates.

- **Classic baseline — Pandolf et al., 1977**  
  https://journals.physiology.org/doi/pdf/10.1152/jappl.1977.43.4.577  
  _Why it matters:_ Historical standard that **under‑predicts** in modern contexts; motivates LCDA preference.

---

## 3) Injury Risk with Rucking / Road Marching (frequency caps, deloads, “one knob/week”)

- **Soldier load carriage — historical/biomedical review (Knapik & Reynolds)**  
  https://academic.oup.com/milmed/article-pdf/169/1/45/21870283/milmed.169.1.45.pdf  
  _Why it matters:_ Summarizes common injuries (feet, knees, back) and risk drivers; supports conservative progressions and foot‑care gates.

- **Strenuous road march injuries (~24% injured)**  
  https://pubmed.ncbi.nlm.nih.gov/1603388/  
  _Why it matters:_ Quantifies risk during high‑demand marches; validates deloading and frequency caps.

- **100‑mile infantry march (~36% injured)**  
  https://pubmed.ncbi.nlm.nih.gov/10048108/  
  _Why it matters:_ Extreme case illustrating how **load × distance × pace** multiplies risk; supports “change one variable at a time.”

- **Special Forces Assessment & Selection — medical encounters by activity**  
  https://pmc.ncbi.nlm.nih.gov/articles/PMC6614812/  
  _Why it matters:_ Shows injury burden of foot marching vs. other PT; justifies substituting **unloaded cardio** on red/amber days.

- **Review — load carriage & MSK injury mechanisms/risk factors (2021)**  
  https://www.mdpi.com/1660-4601/18/8/4010  
  _Why it matters:_ Biomechanics of load (gait, trunk, foot) → supports suitcase carries, posture cues, and terrain choices.

- **Military quantitative physiology (textbook chapter on load carriage)**  
  https://medcoeckapwstorprd01.blob.core.usgovcloudapi.net/pfw-images/borden/mil-quantitative-physiology/QPchapter11.pdf  
  _Why it matters:_ Broad synthesis; reference for clinical/operational reviewers.

---

## 4) Weighted Vests — Body Composition (“Gravitostat” evidence)

- **RCT — EClinicalMedicine (2020): increased weight‑loading ↓ body weight & fat mass in adults with obesity**  
  Full text: https://www.thelancet.com/journals/eclinm/article/PIIS2589-5370(20)30082-1/fulltext  
  PubMed: https://pubmed.ncbi.nlm.nih.gov/32510046/  
  PMC: https://pmc.ncbi.nlm.nih.gov/articles/PMC7264953/  
  _Why it matters:_ Proof‑of‑concept that weight‑loading can aid fat‑loss even without more exercise; informs “Fat loss & feel better” copy.

- **RCT — BMC Medicine (2025): increased weight‑loading improved body composition (↓ fat, ↑ lean) without ↑ activity**  
  https://bmcmedicine.biomedcentral.com/articles/10.1186/s12916-025-04143-6  
  (PMC mirror) https://pmc.ncbi.nlm.nih.gov/articles/PMC12123769/  
  _Why it matters:_ Reinforces body‑comp effects of loading; we still pair with diet/strength for practicality.

---

## 5) Weighted Vests — Bone Outcomes (nuanced)

- **JAMA Network Open (2025) — older adults with obesity during intentional weight loss: weighted vests or RT did **not** prevent hip bone loss over 12 months**  
  Full text: https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2835505  
  PubMed: https://pubmed.ncbi.nlm.nih.gov/40540267/  
  _Why it matters:_ We avoid implying vest‑walking protects hip BMD during dieting; we emphasize resistance/impact and protein.

- **Five‑year program — vest + jumping maintained hip BMD in postmenopausal women**  
  PubMed: https://pubmed.ncbi.nlm.nih.gov/10995045/  
  PDF copy: https://extension.oregonstate.edu/sites/extd8/files/documents/1/snowshawwinterswitzkejgero2000.pdf  
  _Why it matters:_ For bone‑focused users (outside dieting), **impact + load** outperforms load‑only walking; informs “age‑strong” plan notes.

---

## Suggested inline mapping (for your app’s “Why this?” tooltips)

- **Weekly 150–300 min & Zone 2 (40–59% HRR)** → PAG 2nd ed.; ACSM Position Stand.  
- **Prefer time/grade/terrain before heavier loads** → LCDA graded walking + backpacking; vest energetics.  
- **Deload every 4th week; cap ruck frequency** → injury reviews and road‑march incidence papers.  
- **Vest helps fat‑loss but not hip BMD during dieting** → EClinicalMedicine 2020; BMC Medicine 2025; JAMA Net Open 2025.  
- **Add load slowly; only long day progresses** → injury risk scales with load × distance × pace × terrain.

---

### Maintenance
- Update this file quarterly or when new LCDA/USARIEM updates or major guidelines (ACSM/AHA) are released.
