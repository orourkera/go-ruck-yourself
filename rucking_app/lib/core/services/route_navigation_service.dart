import 'dart:math';
import 'dart:async';
import 'package:rucking_app/core/models/route.dart';

/// **Route Navigation Service**
/// 
/// Advanced turn guidance and navigation instructions for route following
/// with voice prompts, distance calculations, and turn detection.
class RouteNavigationService {
  static const double _turnDetectionThreshold = 15.0; // degrees
  static const double _instructionPreviewDistance = 100.0; // meters
  static const double _instructionExecuteDistance = 25.0; // meters
  static const double _recalculationThreshold = 50.0; // meters off route
  
  final Route _route;
  final StreamController<NavigationInstruction> _instructionController;
  
  // Navigation state
  int _currentInstructionIndex = 0;
  List<NavigationInstruction> _instructions = [];
  NavigationInstruction? _currentInstruction;
  NavigationInstruction? _nextInstruction;
  bool _hasPreviewedCurrentInstruction = false;
  
  RouteNavigationService(this._route) 
      : _instructionController = StreamController<NavigationInstruction>.broadcast() {
    _generateNavigationInstructions();
  }
  
  /// 📢 **Navigation Instructions Stream**
  Stream<NavigationInstruction> get instructions => _instructionController.stream;
  
  /// 🎯 **Process Location Update**
  /// 
  /// Analyze current position and provide navigation guidance
  void updateLocation(double latitude, double longitude, {
    double? bearing,
    double? accuracy,
  }) {
    if (_instructions.isEmpty) return;
    
    // Find current position relative to instructions
    _updateCurrentInstruction(latitude, longitude);
    
    // Check if we need to issue instruction
    _checkInstructionTiming(latitude, longitude);
    
    // Handle off-route scenarios
    _handleOffRouteNavigation(latitude, longitude);
  }
  
  /// 🗺️ **Generate Navigation Instructions**
  /// 
  /// Analyze route and create turn-by-turn instructions
  void _generateNavigationInstructions() {
    if (_route.coordinatePoints.length < 3) {
      _instructions = [
        NavigationInstruction(
          id: 'start',
          type: InstructionType.start,
          text: 'Begin your ruck',
          voiceText: 'Start your ruck session',
          distance: 0.0,
          location: _route.coordinatePoints.first,
          bearing: null,
          icon: 'start',
        ),
        NavigationInstruction(
          id: 'finish',
          type: InstructionType.finish,
          text: 'You have arrived at your destination',
          voiceText: 'You have completed your ruck',
          distance: _calculateTotalRouteDistance(),
          location: _route.coordinatePoints.last,
          bearing: null,
          icon: 'finish',
        ),
      ];
      return;
    }
    
    _instructions = [];
    double accumulatedDistance = 0.0;
    
    // Start instruction
    _instructions.add(NavigationInstruction(
      id: 'start',
      type: InstructionType.start,
      text: 'Begin your ruck',
      voiceText: 'Start your ruck session',
      distance: 0.0,
      location: _route.coordinatePoints.first,
      bearing: _calculateInitialBearing(),
      icon: 'start',
    ));
    
    // Analyze route for turns and significant direction changes
    for (int i = 1; i < _route.coordinatePoints.length - 1; i++) {
      final previous = _route.coordinatePoints[i - 1];
      final current = _route.coordinatePoints[i];
      final next = _route.coordinatePoints[i + 1];
      
      // Calculate distance to this point
      accumulatedDistance += _calculateHaversineDistance(
        previous.latitude, previous.longitude,
        current.latitude, current.longitude,
      );
      
      // Calculate bearings
      final incomingBearing = _calculateBearing(
        previous.latitude, previous.longitude,
        current.latitude, current.longitude,
      );
      final outgoingBearing = _calculateBearing(
        current.latitude, current.longitude,
        next.latitude, next.longitude,
      );
      
      // Detect turn
      final turnAngle = _calculateTurnAngle(incomingBearing, outgoingBearing);
      final turnType = _classifyTurn(turnAngle);
      
      if (turnType != TurnType.straight) {
        final instruction = _createTurnInstruction(
          i, turnType, turnAngle, current, accumulatedDistance, outgoingBearing
        );
        _instructions.add(instruction);
      }
      
      // Check for POI instructions
      final poiInstruction = _checkForPOIInstruction(current, accumulatedDistance);
      if (poiInstruction != null) {
        _instructions.add(poiInstruction);
      }
    }
    
    // Finish instruction
    _instructions.add(NavigationInstruction(
      id: 'finish',
      type: InstructionType.finish,
      text: 'You have arrived at your destination',
      voiceText: 'You have completed your ruck',
      distance: accumulatedDistance,
      location: _route.coordinatePoints.last,
      bearing: null,
      icon: 'finish',
    ));
    
    // Sort by distance
    _instructions.sort((a, b) => a.distance.compareTo(b.distance));
  }
  
  /// 🔄 **Create Turn Instruction**
  NavigationInstruction _createTurnInstruction(
    int index,
    TurnType turnType,
    double turnAngle,
    RouteCoordinate location,
    double distance,
    double bearing,
  ) {
    final turnText = _getTurnText(turnType, turnAngle);
    final voiceText = _getTurnVoiceText(turnType, turnAngle);
    final icon = _getTurnIcon(turnType);
    
    return NavigationInstruction(
      id: 'turn_$index',
      type: InstructionType.turn,
      text: turnText,
      voiceText: voiceText,
      distance: distance,
      location: location,
      bearing: bearing,
      icon: icon,
      turnType: turnType,
      turnAngle: turnAngle,
    );
  }
  
  /// 🏛️ **Check for POI Instruction**
  NavigationInstruction? _checkForPOIInstruction(RouteCoordinate location, double distance) {
    for (final poi in _route.pointsOfInterest) {
      final poiDistance = _calculateHaversineDistance(
        location.latitude, location.longitude,
        poi.latitude, poi.longitude,
      );
      
      if (poiDistance <= 25.0) { // Within 25 meters of POI
        return NavigationInstruction(
          id: 'poi_${poi.name.replaceAll(' ', '_').toLowerCase()}',
          type: InstructionType.waypoint,
          text: 'Passing ${poi.name}',
          voiceText: 'You are passing ${poi.name}',
          distance: distance,
          location: location,
          bearing: null,
          icon: 'waypoint',
          waypointName: poi.name,
        );
      }
    }
    return null;
  }
  
  /// 📍 **Update Current Instruction**
  void _updateCurrentInstruction(double latitude, double longitude) {
    final currentLocation = RouteCoordinate(latitude: latitude, longitude: longitude);
    
    // Find the instruction we should be focusing on
    NavigationInstruction? bestInstruction;
    double closestDistance = double.infinity;
    
    for (int i = _currentInstructionIndex; i < _instructions.length; i++) {
      final instruction = _instructions[i];
      final distanceToInstruction = _calculateHaversineDistance(
        latitude, longitude,
        instruction.location.latitude, instruction.location.longitude,
      );
      
      if (distanceToInstruction < closestDistance) {
        closestDistance = distanceToInstruction;
        bestInstruction = instruction;
        _currentInstructionIndex = i;
      }
      
      // If we're past this instruction, move to next
      if (distanceToInstruction > _instructionExecuteDistance * 2) {
        continue;
      } else {
        break;
      }
    }
    
    _currentInstruction = bestInstruction;
    _nextInstruction = _currentInstructionIndex < _instructions.length - 1
        ? _instructions[_currentInstructionIndex + 1]
        : null;
  }
  
  /// ⏱️ **Check Instruction Timing**
  void _checkInstructionTiming(double latitude, double longitude) {
    if (_currentInstruction == null) return;
    
    final distanceToInstruction = _calculateHaversineDistance(
      latitude, longitude,
      _currentInstruction!.location.latitude,
      _currentInstruction!.location.longitude,
    );
    
    // Preview instruction
    if (distanceToInstruction <= _instructionPreviewDistance && 
        !_hasPreviewedCurrentInstruction) {
      _hasPreviewedCurrentInstruction = true;
      _emitInstruction(_currentInstruction!.copyWith(
        phase: InstructionPhase.preview,
        distanceToInstruction: distanceToInstruction,
      ));
    }
    
    // Execute instruction
    if (distanceToInstruction <= _instructionExecuteDistance) {
      _emitInstruction(_currentInstruction!.copyWith(
        phase: InstructionPhase.execute,
        distanceToInstruction: distanceToInstruction,
      ));
      
      // Move to next instruction
      _currentInstructionIndex++;
      _hasPreviewedCurrentInstruction = false;
      
      if (_currentInstructionIndex < _instructions.length) {
        _currentInstruction = _instructions[_currentInstructionIndex];
      } else {
        _currentInstruction = null;
      }
    }
  }
  
  /// 🛣️ **Handle Off-Route Navigation**
  void _handleOffRouteNavigation(double latitude, double longitude) {
    // Find closest point on route
    final closestResult = _findClosestPointOnRoute(latitude, longitude);
    final distanceToRoute = closestResult['distance'] as double;
    
    if (distanceToRoute > _recalculationThreshold) {
      // Emit off-route instruction
      _emitInstruction(NavigationInstruction(
        id: 'off_route',
        type: InstructionType.offRoute,
        text: 'Return to route',
        voiceText: 'You are off route. Return to the planned path.',
        distance: 0.0,
        location: RouteCoordinate(latitude: latitude, longitude: longitude),
        bearing: _calculateBearingToRoute(latitude, longitude),
        icon: 'return',
        distanceToInstruction: distanceToRoute,
        phase: InstructionPhase.execute,
      ));
    }
  }
  
  /// 🎯 **Find Closest Point on Route**
  Map<String, dynamic> _findClosestPointOnRoute(double latitude, double longitude) {
    if (_route.coordinatePoints.isEmpty) {
      return {'distance': double.infinity, 'index': 0, 'point': null};
    }
    
    double minDistance = double.infinity;
    int closestIndex = 0;
    RouteCoordinate? closestPoint;
    
    for (int i = 0; i < _route.coordinatePoints.length; i++) {
      final point = _route.coordinatePoints[i];
      final distance = _calculateHaversineDistance(
        latitude, longitude, point.latitude, point.longitude
      );
      
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
        closestPoint = point;
      }
    }
    
    return {'distance': minDistance, 'index': closestIndex, 'point': closestPoint};
  }
  
  /// 🧭 **Calculate Bearing to Route**
  double _calculateBearingToRoute(double latitude, double longitude) {
    final closestResult = _findClosestPointOnRoute(latitude, longitude);
    final closestPoint = closestResult['point'] as RouteCoordinate?;
    
    if (closestPoint == null) return 0.0;
    
    return _calculateBearing(
      latitude, longitude,
      closestPoint.latitude, closestPoint.longitude,
    );
  }
  
  /// 📐 **Calculate Bearing**
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * (math.pi / 180);
    final lat1Rad = lat1 * (math.pi / 180);
    final lat2Rad = lat2 * (math.pi / 180);
    
    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);
    
    final bearing = math.atan2(y, x) * (180 / math.pi);
    return (bearing + 360) % 360;
  }
  
  /// 🔄 **Calculate Turn Angle**
  double _calculateTurnAngle(double incomingBearing, double outgoingBearing) {
    double turnAngle = outgoingBearing - incomingBearing;
    
    // Normalize to -180 to 180
    while (turnAngle > 180) turnAngle -= 360;
    while (turnAngle < -180) turnAngle += 360;
    
    return turnAngle;
  }
  
  /// 🔄 **Classify Turn**
  TurnType _classifyTurn(double turnAngle) {
    final absoluteAngle = turnAngle.abs();
    
    if (absoluteAngle < _turnDetectionThreshold) {
      return TurnType.straight;
    } else if (absoluteAngle <= 45) {
      return turnAngle > 0 ? TurnType.slightLeft : TurnType.slightRight;
    } else if (absoluteAngle <= 120) {
      return turnAngle > 0 ? TurnType.left : TurnType.right;
    } else {
      return turnAngle > 0 ? TurnType.sharpLeft : TurnType.sharpRight;
    }
  }
  
  /// 📝 **Get Turn Text**
  String _getTurnText(TurnType turnType, double turnAngle) {
    switch (turnType) {
      case TurnType.straight:
        return 'Continue straight';
      case TurnType.slightLeft:
        return 'Turn slightly left';
      case TurnType.left:
        return 'Turn left';
      case TurnType.sharpLeft:
        return 'Turn sharp left';
      case TurnType.slightRight:
        return 'Turn slightly right';
      case TurnType.right:
        return 'Turn right';
      case TurnType.sharpRight:
        return 'Turn sharp right';
      case TurnType.uTurn:
        return 'Make a U-turn';
    }
  }
  
  /// 🔊 **Get Turn Voice Text**
  String _getTurnVoiceText(TurnType turnType, double turnAngle) {
    switch (turnType) {
      case TurnType.straight:
        return 'Continue straight ahead';
      case TurnType.slightLeft:
        return 'Turn slightly to the left';
      case TurnType.left:
        return 'Turn left';
      case TurnType.sharpLeft:
        return 'Turn sharp left';
      case TurnType.slightRight:
        return 'Turn slightly to the right';
      case TurnType.right:
        return 'Turn right';
      case TurnType.sharpRight:
        return 'Turn sharp right';
      case TurnType.uTurn:
        return 'Make a U-turn when possible';
    }
  }
  
  /// 🎨 **Get Turn Icon**
  String _getTurnIcon(TurnType turnType) {
    switch (turnType) {
      case TurnType.straight:
        return 'arrow_upward';
      case TurnType.slightLeft:
        return 'turn_slight_left';
      case TurnType.left:
        return 'turn_left';
      case TurnType.sharpLeft:
        return 'turn_sharp_left';
      case TurnType.slightRight:
        return 'turn_slight_right';
      case TurnType.right:
        return 'turn_right';
      case TurnType.sharpRight:
        return 'turn_sharp_right';
      case TurnType.uTurn:
        return 'u_turn_left';
    }
  }
  
  /// 📏 **Calculate Route Distance**
  double _calculateTotalRouteDistance() {
    if (_route.coordinatePoints.length < 2) return 0.0;
    
    double totalDistance = 0.0;
    for (int i = 0; i < _route.coordinatePoints.length - 1; i++) {
      final current = _route.coordinatePoints[i];
      final next = _route.coordinatePoints[i + 1];
      totalDistance += _calculateHaversineDistance(
        current.latitude, current.longitude, next.latitude, next.longitude
      );
    }
    return totalDistance;
  }
  
  /// 🧭 **Calculate Initial Bearing**
  double _calculateInitialBearing() {
    if (_route.coordinatePoints.length < 2) return 0.0;
    
    final start = _route.coordinatePoints[0];
    final second = _route.coordinatePoints[1];
    
    return _calculateBearing(
      start.latitude, start.longitude, second.latitude, second.longitude
    );
  }
  
  /// 📐 **Calculate Haversine Distance**
  double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) * math.cos(lat2 * (math.pi / 180)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
  
  /// 📢 **Emit Instruction**
  void _emitInstruction(NavigationInstruction instruction) {
    _instructionController.add(instruction);
  }
  
  /// 🔄 **Reset Navigation**
  void reset() {
    _currentInstructionIndex = 0;
    _currentInstruction = null;
    _nextInstruction = null;
    _hasPreviewedCurrentInstruction = false;
  }
  
  /// 🗑️ **Dispose Resources**
  void dispose() {
    _instructionController.close();
  }
  
  /// 📋 **Get All Instructions**
  List<NavigationInstruction> getAllInstructions() {
    return List.unmodifiable(_instructions);
  }
  
  /// 📍 **Get Current Instruction**
  NavigationInstruction? getCurrentInstruction() {
    return _currentInstruction;
  }
  
  /// ➡️ **Get Next Instruction**
  NavigationInstruction? getNextInstruction() {
    return _nextInstruction;
  }
}

/// 🧭 **Navigation Instruction**
class NavigationInstruction {
  final String id;
  final InstructionType type;
  final String text;
  final String voiceText;
  final double distance; // Distance from route start
  final RouteCoordinate location;
  final double? bearing;
  final String icon;
  final TurnType? turnType;
  final double? turnAngle;
  final String? waypointName;
  final InstructionPhase phase;
  final double? distanceToInstruction;
  
  const NavigationInstruction({
    required this.id,
    required this.type,
    required this.text,
    required this.voiceText,
    required this.distance,
    required this.location,
    this.bearing,
    required this.icon,
    this.turnType,
    this.turnAngle,
    this.waypointName,
    this.phase = InstructionPhase.pending,
    this.distanceToInstruction,
  });
  
  NavigationInstruction copyWith({
    InstructionPhase? phase,
    double? distanceToInstruction,
  }) {
    return NavigationInstruction(
      id: id,
      type: type,
      text: text,
      voiceText: voiceText,
      distance: distance,
      location: location,
      bearing: bearing,
      icon: icon,
      turnType: turnType,
      turnAngle: turnAngle,
      waypointName: waypointName,
      phase: phase ?? this.phase,
      distanceToInstruction: distanceToInstruction ?? this.distanceToInstruction,
    );
  }
}

/// 📝 **Instruction Types**
enum InstructionType {
  start,
  turn,
  waypoint,
  offRoute,
  reroute,
  finish,
}

/// 🔄 **Turn Types**
enum TurnType {
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
}

/// ⏱️ **Instruction Phases**
enum InstructionPhase {
  pending,   // Not yet relevant
  preview,   // Show preview (100m away)
  execute,   // Execute instruction (25m away)
  completed, // Instruction completed
}
