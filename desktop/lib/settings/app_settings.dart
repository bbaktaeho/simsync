class AppSettings {
  static const double minContentScale = 0.8;
  static const double maxContentScale = 2.0;
  static const int minSyncIntervalSeconds = 5;
  static const int maxSyncIntervalSeconds = 300;

  final String localNotePath;
  final double contentScale;
  final int syncIntervalSeconds;
  final bool syncEnabled;

  const AppSettings({
    required this.localNotePath,
    required this.contentScale,
    required this.syncIntervalSeconds,
    required this.syncEnabled,
  });

  AppSettings copyWith({
    String? localNotePath,
    double? contentScale,
    int? syncIntervalSeconds,
    bool? syncEnabled,
  }) {
    return AppSettings(
      localNotePath: localNotePath ?? this.localNotePath,
      contentScale: contentScale ?? this.contentScale,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
      syncEnabled: syncEnabled ?? this.syncEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppSettings &&
        other.localNotePath == localNotePath &&
        other.contentScale == contentScale &&
        other.syncIntervalSeconds == syncIntervalSeconds &&
        other.syncEnabled == syncEnabled;
  }

  @override
  int get hashCode => Object.hash(
    localNotePath,
    contentScale,
    syncIntervalSeconds,
    syncEnabled,
  );
}
