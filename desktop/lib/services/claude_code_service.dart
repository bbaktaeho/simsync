import 'dart:async';
import 'dart:io';

import 'cli_process.dart';

/// Raised when the Claude Code CLI cannot be run or returns an error. The
/// [message] is safe to surface directly to the user.
class ClaudeCodeException implements Exception {
  ClaudeCodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Captured result of a single CLI invocation (shared with the Codex service;
/// the alias keeps the original public name).
typedef ClaudeProcessResult = CliProcessResult;

/// Injectable process runner (see [CliProcessRunner]); the alias keeps the
/// original public name.
typedef ClaudeProcessRunner = CliProcessRunner;

/// Thin wrapper around the Claude Code headless CLI (`claude --print`).
///
/// The summary is produced with the documented pipe pattern
/// `cat <notes> | claude -p "<instruction>"`: the instruction is the positional
/// prompt and the period's notes are streamed via stdin (no ARG_MAX limit).
class ClaudeCodeService {
  ClaudeCodeService({ClaudeProcessRunner? runner}) : _run = runner ?? runCliProcess;

  final ClaudeProcessRunner _run;

  static const Duration summaryTimeout = Duration(seconds: 180);
  static const Duration versionTimeout = Duration(seconds: 10);

  /// Upper bound on the piped notes context. Keeps latency, cost and memory
  /// bounded even when a period holds an unusually large amount of text.
  static const int maxContextChars = 200000;

  /// Every file/shell/network/sub-agent tool. The notes are piped in via
  /// stdin, so the model never needs to touch the filesystem — denying these
  /// guarantees it cannot read other notes, the repo, or any path outside the
  /// provided context, and (since nothing requires approval) it never blocks on
  /// a permission prompt in headless mode.
  static const List<String> deniedTools = [
    'Read',
    'Edit',
    'Write',
    'Bash',
    'Glob',
    'Grep',
    'WebFetch',
    'WebSearch',
    'Task',
    'NotebookEdit',
  ];

  String _resolveExecutable(String? cliPath) {
    final trimmed = cliPath?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    // GUI apps launched from Finder do not inherit the shell PATH, so a bare
    // `claude` may not resolve. Probe common install locations first; fall back
    // to `claude` (which works when launched from a shell that has it on PATH).
    final home = Platform.environment['HOME'];
    final candidates = <String>[
      '/opt/homebrew/bin/claude',
      '/usr/local/bin/claude',
      if (home != null) '$home/.claude/local/claude',
      if (home != null) '$home/.local/bin/claude',
      '/usr/bin/claude',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return 'claude';
  }

  /// Builds a PATH for spawning [executable] that survives a Finder launch.
  /// Kept as a public static for compatibility; see [buildCliPathEnv].
  static String buildPathEnv(String executable, String? currentPath, String? home) =>
      buildCliPathEnv(executable, currentPath, home);

  /// Whether the Claude Code CLI is reachable (`claude --version` exits 0).
  Future<bool> isAvailable({String? cliPath}) async {
    try {
      final result = await _run(
        _resolveExecutable(cliPath),
        const ['--version'],
        timeout: versionTimeout,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Runs one summary pass. Throws [ClaudeCodeException] with a user-facing
  /// message on any failure (missing CLI, timeout, non-zero exit, empty reply).
  Future<String> summarizeWeek({
    required String instruction,
    required String notesContext,
    String? cliPath,
    String? model,
  }) async {
    final exe = _resolveExecutable(cliPath);
    final trimmedInstruction = instruction.trim();
    if (trimmedInstruction.isEmpty) {
      throw ClaudeCodeException('AI 지침이 비어 있습니다. 설정 > AI에서 지침을 입력하세요.');
    }
    if (notesContext.trim().isEmpty) {
      throw ClaudeCodeException('요약할 노트가 없습니다.');
    }

    var context = notesContext;
    if (context.length > maxContextChars) {
      context = context.substring(0, maxContextChars);
    }

    final model0 = model?.trim() ?? '';
    final args = <String>[
      '--print',
      // Deny every file/shell/network tool (the variadic flag stops at the next
      // option). The notes are the only context, provided on stdin.
      '--disallowedTools',
      ...deniedTools,
      '--output-format',
      'text',
      // One-off run — don't leave a resumable session on disk.
      '--no-session-persistence',
      if (model0.isNotEmpty) ...['--model', model0],
      trimmedInstruction,
    ];

    final ClaudeProcessResult result;
    try {
      result = await _run(
        exe,
        args,
        stdinText: context,
        timeout: summaryTimeout,
      );
    } on ProcessException catch (e) {
      throw ClaudeCodeException(
        'Claude Code 실행 파일을 찾을 수 없습니다 ($exe).\n'
        '설정 > AI에서 CLI 경로를 지정하거나 PATH에 claude를 추가하세요.\n${e.message}',
      );
    } on TimeoutException {
      throw ClaudeCodeException('Claude Code 응답이 시간 초과되었습니다 (${summaryTimeout.inSeconds}s).');
    }

    if (result.exitCode != 0) {
      final detail = result.stderr.trim().isNotEmpty
          ? result.stderr.trim()
          : result.stdout.trim();
      throw ClaudeCodeException(
        'Claude Code 오류 (exit ${result.exitCode}).\n$detail',
      );
    }

    final output = result.stdout.trim();
    if (output.isEmpty) {
      throw ClaudeCodeException('Claude Code가 빈 응답을 반환했습니다.');
    }
    return output;
  }
}
