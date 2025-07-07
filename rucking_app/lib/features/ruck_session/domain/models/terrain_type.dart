enum TerrainType {
  road,
  trail,
  track,
  grass,
  gravel,
  sand,
  mud,
  snow,
  ice,
  unknown
}

extension TerrainTypeExtension on TerrainType {
  String get displayName {
    switch (this) {
      case TerrainType.road:
        return 'Road';
      case TerrainType.trail:
        return 'Trail';
      case TerrainType.track:
        return 'Track';
      case TerrainType.grass:
        return 'Grass';
      case TerrainType.gravel:
        return 'Gravel';
      case TerrainType.sand:
        return 'Sand';
      case TerrainType.mud:
        return 'Mud';
      case TerrainType.snow:
        return 'Snow';
      case TerrainType.ice:
        return 'Ice';
      case TerrainType.unknown:
        return 'Unknown';
    }
  }
}
