class AppSettings {
  static const double minContentScale = 0.8;
  static const double maxContentScale = 2.0;
  static const int minSyncIntervalSeconds = 5;
  static const int maxSyncIntervalSeconds = 300;
  static const int defaultSearchContextLines = 3;
  static const int minSearchContextLines = 1;
  static const int maxSearchContextLines = 10;

  /// Default instruction used to generate the weekly summary.
  static const String defaultWeeklyInstruction =
      '아래는 이번 주(월~일) 동안 작성한 노트입니다. '
      '이 기록을 바탕으로 이번 주에 한 일을 카테고리별로 정리하고, '
      '주요 성과와 다음 주에 이어갈 일을 간결하게 요약해 주세요. '
      '한국어로 작성하고, 핵심만 불릿으로 정리하세요.';

  /// Default instruction used to generate the monthly summary. The input is the
  /// month's weekly reviews (or notes when none exist).
  static const String defaultMonthlyInstruction =
      '아래는 이번 달 동안 작성한 주간 리뷰(또는 노트)입니다. '
      '이 기록을 바탕으로 이번 달의 주요 성과와 배운 점을 주제별로 정리하고, '
      '다음 달에 이어갈 목표를 간결하게 정리해 주세요. '
      '한국어로 작성하고, 핵심만 불릿으로 정리하세요.';

  /// Weekly summary provider. [providerApi] calls the Anthropic Messages API
  /// directly with an API key (robust, works from a GUI app). [providerCli]
  /// shells out to the Claude Code CLI (uses a Claude.ai subscription when the
  /// CLI is logged in via subscription).
  static const String providerApi = 'api';
  static const String providerCli = 'cli';

  /// Default Anthropic model for the API provider.
  static const String defaultAnthropicModel = 'claude-opus-4-8';

  final String localNotePath;
  final double contentScale;
  final int syncIntervalSeconds;
  final bool syncEnabled;
  final int searchContextLines;

  /// Instruction text sent to the model when generating the weekly summary.
  final String weeklyInstruction;

  /// Instruction text sent to the model when generating the monthly summary.
  final String monthlyInstruction;

  /// Whether the weekly-summary AI integration is enabled.
  final bool claudeCodeEnabled;

  /// Optional absolute path to the `claude` CLI. Empty means auto-detect.
  final String claudeCliPath;

  /// Selected weekly summary provider: [providerApi] or [providerCli].
  final String weeklyProvider;

  /// Anthropic API key (`sk-ant-...`) for the API provider.
  final String anthropicApiKey;

  /// Anthropic model id for the API provider.
  final String anthropicModel;

  const AppSettings({
    required this.localNotePath,
    required this.contentScale,
    required this.syncIntervalSeconds,
    required this.syncEnabled,
    this.searchContextLines = defaultSearchContextLines,
    this.weeklyInstruction = defaultWeeklyInstruction,
    this.monthlyInstruction = defaultMonthlyInstruction,
    this.claudeCodeEnabled = false,
    this.claudeCliPath = '',
    this.weeklyProvider = providerApi,
    this.anthropicApiKey = '',
    this.anthropicModel = defaultAnthropicModel,
  });

  AppSettings copyWith({
    String? localNotePath,
    double? contentScale,
    int? syncIntervalSeconds,
    bool? syncEnabled,
    int? searchContextLines,
    String? weeklyInstruction,
    String? monthlyInstruction,
    bool? claudeCodeEnabled,
    String? claudeCliPath,
    String? weeklyProvider,
    String? anthropicApiKey,
    String? anthropicModel,
  }) {
    return AppSettings(
      localNotePath: localNotePath ?? this.localNotePath,
      contentScale: contentScale ?? this.contentScale,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      searchContextLines: searchContextLines ?? this.searchContextLines,
      weeklyInstruction: weeklyInstruction ?? this.weeklyInstruction,
      monthlyInstruction: monthlyInstruction ?? this.monthlyInstruction,
      claudeCodeEnabled: claudeCodeEnabled ?? this.claudeCodeEnabled,
      claudeCliPath: claudeCliPath ?? this.claudeCliPath,
      weeklyProvider: weeklyProvider ?? this.weeklyProvider,
      anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
      anthropicModel: anthropicModel ?? this.anthropicModel,
    );
  }

  /// The portable, device-agnostic settings — the only fields that are exported
  /// to JSON and synced via `settings/settings.json`.
  ///
  /// Deliberately EXCLUDES [anthropicApiKey] (a secret that must never be
  /// committed to the synced repo) and [localNotePath] / [claudeCliPath]
  /// (device-specific paths that differ per machine). Those stay local-only.
  Map<String, Object?> toSyncJson() => {
        'contentScale': contentScale,
        'syncIntervalSeconds': syncIntervalSeconds,
        'syncEnabled': syncEnabled,
        'searchContextLines': searchContextLines,
        'weeklyInstruction': weeklyInstruction,
        'monthlyInstruction': monthlyInstruction,
        'claudeCodeEnabled': claudeCodeEnabled,
        'weeklyProvider': weeklyProvider,
        'anthropicModel': anthropicModel,
      };

  /// Keys carried by [toSyncJson]; used to validate/round-trip imports.
  static const List<String> syncJsonKeys = [
    'contentScale',
    'syncIntervalSeconds',
    'syncEnabled',
    'searchContextLines',
    'weeklyInstruction',
    'monthlyInstruction',
    'claudeCodeEnabled',
    'weeklyProvider',
    'anthropicModel',
  ];

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
        other.monthlyInstruction == monthlyInstruction &&
        other.claudeCodeEnabled == claudeCodeEnabled &&
        other.claudeCliPath == claudeCliPath &&
        other.weeklyProvider == weeklyProvider &&
        other.anthropicApiKey == anthropicApiKey &&
        other.anthropicModel == anthropicModel;
  }

  @override
  int get hashCode => Object.hash(
    localNotePath,
    contentScale,
    syncIntervalSeconds,
    syncEnabled,
    searchContextLines,
    weeklyInstruction,
    monthlyInstruction,
    claudeCodeEnabled,
    claudeCliPath,
    weeklyProvider,
    anthropicApiKey,
    anthropicModel,
  );
}
