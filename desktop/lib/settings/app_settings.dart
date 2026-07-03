/// User's theme preference. [system] follows the macOS appearance; [light] and
/// [dark] force that mode. Stored locally (device-specific), not synced.
enum AppThemeMode { system, light, dark }

class AppSettings {
  static const double minContentScale = 0.8;
  static const double maxContentScale = 2.0;
  static const int minSyncIntervalSeconds = 5;
  static const int maxSyncIntervalSeconds = 300;
  static const int defaultSearchContextLines = 3;
  static const int minSearchContextLines = 1;
  static const int maxSearchContextLines = 10;

  /// SYSTEM instruction for stage 1 (the "outline" pass) of the WEEKLY review.
  /// Fixed in code and NOT user-editable — only the stage-2 instruction
  /// ([weeklyInstruction]) is. It exhaustively gathers everything done that week
  /// and emits a GitHub-checkbox list of the key titles; the items the user
  /// keeps checked then feed stage 2.
  static const String weeklyOutlineSystemInstruction = '''
당신은 한 주의 업무 기록을 빠짐없이 정리하는 보조자입니다.
아래는 이번 주(월~일)에 작성된 노트와 메모입니다.

수행할 작업:
1. 이번 주에 다룬 주제, 활동, 결정, 이슈, 진행 상황을 빠짐없이 식별합니다. 사소해 보여도 누락하지 마세요.
2. 비슷한 항목은 하나의 핵심 항목으로 묶되, 맥락이 다르면 분리합니다.
3. 각 핵심 항목을 GitHub 체크박스 한 줄로 출력합니다: "- [ ] (MM-DD) 핵심 제목 — 한 줄 요약"

규칙:
- 출력은 체크박스 목록만 포함합니다. 서문, 맺음말, 그 외 설명을 넣지 마세요.
- (MM-DD)는 그 항목과 관련된 날짜이며, 입력 노트의 날짜(YYYY-MM-DD)에 근거합니다. 하루면 "06-02", 여러 날에 걸치면 "06-02 ~ 06-05"처럼 범위로 적습니다.
- 제목은 명사형으로 간결하게 쓰고, 요약은 실제 기록에 근거합니다. 추측하거나 지어내지 마세요.
- 한국어로 작성합니다.''';

  /// SYSTEM instruction for stage 1 of the MONTHLY review. Fixed in code. The
  /// input is the month's weekly outlines/reviews (or notes when none exist).
  static const String monthlyOutlineSystemInstruction = '''
당신은 한 달의 업무 기록을 빠짐없이 정리하는 보조자입니다.
아래는 이번 달의 주별 핵심 정리(또는 노트)입니다.

수행할 작업:
1. 이번 달에 다룬 주요 주제, 성과, 결정, 이슈, 진행 상황을 빠짐없이 식별합니다.
2. 여러 주에 걸쳐 이어진 흐름은 하나의 핵심 항목으로 묶습니다.
3. 각 핵심 항목을 GitHub 체크박스 한 줄로 출력합니다: "- [ ] (MM-DD) 핵심 제목 — 한 줄 요약"

규칙:
- 출력은 체크박스 목록만 포함합니다. 서문, 맺음말, 그 외 설명을 넣지 마세요.
- (MM-DD)는 그 항목과 관련된 날짜(또는 범위)이며, 입력의 날짜에 근거합니다. 하루면 "06-02", 여러 날/주에 걸치면 "06-02 ~ 06-12"처럼 범위로 적습니다.
- 실제 기록에 근거하며, 추측하거나 지어내지 마세요.
- 한국어로 작성합니다.''';

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

  /// AI review provider (weekly + monthly). [providerApi] calls the Anthropic
  /// Messages API directly with an API key (robust, works from a GUI app).
  /// [providerCli] shells out to the Claude Code CLI (uses a Claude.ai
  /// subscription when the CLI is logged in via subscription). [providerCodex]
  /// shells out to the OpenAI Codex CLI (`codex exec`, ChatGPT subscription).
  static const String providerApi = 'api';
  static const String providerCli = 'cli';
  static const String providerCodex = 'codex';

  /// Default model for the stage-2 review (Sonnet — balanced; Opus is overkill
  /// for summarization). User-overridable in settings. Applies to the Anthropic
  /// API and Claude CLI providers only — Codex always uses its own default.
  static const String defaultAnthropicModel = 'claude-sonnet-4-6';

  /// Fixed fast, cheap model for the stage-1 outline (simple extraction/recall).
  static const String outlineModel = 'claude-haiku-4-5';

  final String localNotePath;
  final double contentScale;
  final int syncIntervalSeconds;
  final bool syncEnabled;
  final int searchContextLines;

  /// Instruction text sent to the model when generating the weekly summary.
  final String weeklyInstruction;

  /// Instruction text sent to the model when generating the monthly summary.
  final String monthlyInstruction;

  /// Whether the AI review integration (weekly + monthly) is enabled.
  final bool aiEnabled;

  /// Optional absolute path to the `claude` CLI. Empty means auto-detect.
  final String claudeCliPath;

  /// Optional absolute path to the `codex` CLI. Empty means auto-detect.
  final String codexCliPath;

  /// Selected AI provider: [providerApi], [providerCli] or [providerCodex].
  final String aiProvider;

  /// Anthropic API key (`sk-ant-...`) for the API provider.
  final String anthropicApiKey;

  /// Anthropic model id for the API provider.
  final String anthropicModel;

  /// Theme preference (device-local, not synced). Defaults to following the OS.
  final AppThemeMode themeMode;

  const AppSettings({
    required this.localNotePath,
    required this.contentScale,
    required this.syncIntervalSeconds,
    required this.syncEnabled,
    this.searchContextLines = defaultSearchContextLines,
    this.weeklyInstruction = defaultWeeklyInstruction,
    this.monthlyInstruction = defaultMonthlyInstruction,
    this.aiEnabled = false,
    this.claudeCliPath = '',
    this.codexCliPath = '',
    this.aiProvider = providerApi,
    this.anthropicApiKey = '',
    this.anthropicModel = defaultAnthropicModel,
    this.themeMode = AppThemeMode.system,
  });

  AppSettings copyWith({
    String? localNotePath,
    double? contentScale,
    int? syncIntervalSeconds,
    bool? syncEnabled,
    int? searchContextLines,
    String? weeklyInstruction,
    String? monthlyInstruction,
    bool? aiEnabled,
    String? claudeCliPath,
    String? codexCliPath,
    String? aiProvider,
    String? anthropicApiKey,
    String? anthropicModel,
    AppThemeMode? themeMode,
  }) {
    return AppSettings(
      localNotePath: localNotePath ?? this.localNotePath,
      contentScale: contentScale ?? this.contentScale,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      searchContextLines: searchContextLines ?? this.searchContextLines,
      weeklyInstruction: weeklyInstruction ?? this.weeklyInstruction,
      monthlyInstruction: monthlyInstruction ?? this.monthlyInstruction,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      claudeCliPath: claudeCliPath ?? this.claudeCliPath,
      codexCliPath: codexCliPath ?? this.codexCliPath,
      aiProvider: aiProvider ?? this.aiProvider,
      anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
      anthropicModel: anthropicModel ?? this.anthropicModel,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  /// The portable, device-agnostic settings — the only fields that are exported
  /// to JSON and synced via `settings/settings.json`.
  ///
  /// Deliberately EXCLUDES [anthropicApiKey] (a secret that must never be
  /// committed to the synced repo) and [localNotePath] / [claudeCliPath] /
  /// [codexCliPath] (device-specific paths that differ per machine). Those stay
  /// local-only.
  Map<String, Object?> toSyncJson() => {
        'contentScale': contentScale,
        'syncIntervalSeconds': syncIntervalSeconds,
        'syncEnabled': syncEnabled,
        'searchContextLines': searchContextLines,
        'weeklyInstruction': weeklyInstruction,
        'monthlyInstruction': monthlyInstruction,
        'aiEnabled': aiEnabled,
        'aiProvider': aiProvider,
        'anthropicModel': anthropicModel,
      };

  /// Keys carried by [toSyncJson]; used to validate/round-trip imports.
  /// Imports additionally accept the legacy `claudeCodeEnabled` /
  /// `weeklyProvider` keys from JSON exported by older builds.
  static const List<String> syncJsonKeys = [
    'contentScale',
    'syncIntervalSeconds',
    'syncEnabled',
    'searchContextLines',
    'weeklyInstruction',
    'monthlyInstruction',
    'aiEnabled',
    'aiProvider',
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
        other.aiEnabled == aiEnabled &&
        other.claudeCliPath == claudeCliPath &&
        other.codexCliPath == codexCliPath &&
        other.aiProvider == aiProvider &&
        other.anthropicApiKey == anthropicApiKey &&
        other.anthropicModel == anthropicModel &&
        other.themeMode == themeMode;
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
    aiEnabled,
    claudeCliPath,
    codexCliPath,
    aiProvider,
    anthropicApiKey,
    anthropicModel,
    themeMode,
  );
}
