class AppSettings {
  static const double minContentScale = 0.8;
  static const double maxContentScale = 2.0;
  static const int minSyncIntervalSeconds = 5;
  static const int maxSyncIntervalSeconds = 300;
  static const int defaultSearchContextLines = 3;
  static const int minSearchContextLines = 1;
  static const int maxSearchContextLines = 10;

  /// Default instruction used to generate the weekly summary via Claude Code.
  static const String defaultWeeklyInstruction =
      '아래는 이번 주(월~일) 동안 작성한 노트입니다. '
      '이 기록을 바탕으로 이번 주에 한 일을 카테고리별로 정리하고, '
      '주요 성과와 다음 주에 이어갈 일을 간결하게 요약해 주세요. '
      '한국어로 작성하고, 핵심만 불릿으로 정리하세요.';

  final String localNotePath;
  final double contentScale;
  final int syncIntervalSeconds;
  final bool syncEnabled;
  final int searchContextLines;

  /// Instruction text sent to Claude Code when generating the weekly summary.
  final String weeklyInstruction;

  /// Whether the Claude Code weekly-summary integration is enabled.
  final bool claudeCodeEnabled;

  /// Optional absolute path to the `claude` CLI. Empty means "use `claude` from
  /// PATH". Useful on macOS where GUI apps do not inherit the shell PATH.
  final String claudeCliPath;

  const AppSettings({
    required this.localNotePath,
    required this.contentScale,
    required this.syncIntervalSeconds,
    required this.syncEnabled,
    this.searchContextLines = defaultSearchContextLines,
    this.weeklyInstruction = defaultWeeklyInstruction,
    this.claudeCodeEnabled = false,
    this.claudeCliPath = '',
  });

  AppSettings copyWith({
    String? localNotePath,
    double? contentScale,
    int? syncIntervalSeconds,
    bool? syncEnabled,
    int? searchContextLines,
    String? weeklyInstruction,
    bool? claudeCodeEnabled,
    String? claudeCliPath,
  }) {
    return AppSettings(
      localNotePath: localNotePath ?? this.localNotePath,
      contentScale: contentScale ?? this.contentScale,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      searchContextLines: searchContextLines ?? this.searchContextLines,
      weeklyInstruction: weeklyInstruction ?? this.weeklyInstruction,
      claudeCodeEnabled: claudeCodeEnabled ?? this.claudeCodeEnabled,
      claudeCliPath: claudeCliPath ?? this.claudeCliPath,
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
        other.searchContextLines == searchContextLines &&
        other.weeklyInstruction == weeklyInstruction &&
        other.claudeCodeEnabled == claudeCodeEnabled &&
        other.claudeCliPath == claudeCliPath;
  }

  @override
  int get hashCode => Object.hash(
    localNotePath,
    contentScale,
    syncIntervalSeconds,
    syncEnabled,
    searchContextLines,
    weeklyInstruction,
    claudeCodeEnabled,
    claudeCliPath,
  );
}
