class AppSettings {
  static const double minContentScale = 0.8;
  static const double maxContentScale = 2.0;
  static const int minSyncIntervalSeconds = 5;
  static const int maxSyncIntervalSeconds = 300;
  static const int defaultSearchContextLines = 3;
  static const int minSearchContextLines = 1;
  static const int maxSearchContextLines = 10;

  final String localNotePath;
  final double contentScale;
  final int syncIntervalSeconds;
  final bool syncEnabled;
  final int searchContextLines;

  const AppSettings({
    required this.localNotePath,
    required this.contentScale,
    required this.syncIntervalSeconds,
    required this.syncEnabled,
    this.searchContextLines = defaultSearchContextLines,
  });

  AppSettings copyWith({
    String? localNotePath,
    double? contentScale,
    int? syncIntervalSeconds,
    bool? syncEnabled,
    int? searchContextLines,
  }) {
    return AppSettings(
      localNotePath: localNotePath ?? this.localNotePath,
      contentScale: contentScale ?? this.contentScale,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      searchContextLines: searchContextLines ?? this.searchContextLines,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppSettings &&
        other.localNotePath == localNotePath &&
        other.contentScale == contentScale &&
        other.syncIntervalSeconds == syncIntervalSeconds &&
        other.syncEnabled == syncEnabled &&
        other.searchContextLines == searchContextLines;
  }

  @override
  int get hashCode => Object.hash(
    localNotePath,
    contentScale,
    syncIntervalSeconds,
    syncEnabled,
    searchContextLines,
  );
}
