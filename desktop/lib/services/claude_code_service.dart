import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Raised when the Claude Code CLI cannot be run or returns an error. The
/// [message] is safe to surface directly to the user.
class ClaudeCodeException implements Exception {
  ClaudeCodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Captured result of a single CLI invocation.
class ClaudeProcessResult {
  const ClaudeProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs an external process, optionally feeding [stdinText], and returns the
/// captured result. Injectable so [ClaudeCodeService] is unit-testable without
/// a real Claude Code install.
typedef ClaudeProcessRunner = Future<ClaudeProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? stdinText,
  Duration? timeout,
});

/// Thin wrapper around the Claude Code headless CLI (`claude --print`).
///
/// The weekly summary is produced with the documented pipe pattern
/// `cat <notes> | claude -p "<instruction>"`: the instruction is the positional
/// prompt and the week's notes are streamed via stdin (no ARG_MAX limit).
class ClaudeCodeService {
  ClaudeCodeService({ClaudeProcessRunner? runner})
    : _run = runner ?? _defaultRunner;

  final ClaudeProcessRunner _run;

  static const Duration summaryTimeout = Duration(seconds: 180);
  static const Duration versionTimeout = Duration(seconds: 10);

  /// Upper bound on the piped notes context. Keeps latency, cost and memory
  /// bounded even when a week holds an unusually large amount of text.
  static const int maxContextChars = 200000;

  String _resolveExecutable(String? cliPath) {
    final trimmed = cliPath?.trim() ?? '';
    return trimmed.isEmpty ? 'claude' : trimmed;
  }

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

  /// Runs the weekly summary. Throws [ClaudeCodeException] with a user-facing
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
      throw ClaudeCodeException('위클리 지침이 비어 있습니다. 설정 > Weekly에서 지침을 입력하세요.');
    }
    if (notesContext.trim().isEmpty) {
      throw ClaudeCodeException('이번 주에 요약할 노트가 없습니다.');
    }

    var context = notesContext;
    if (context.length > maxContextChars) {
      context = context.substring(0, maxContextChars);
    }

    final model0 = model?.trim() ?? '';
    final args = <String>[
      '--print',
      '--output-format',
      'text',
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
        '설정 > Weekly에서 CLI 경로를 지정하거나 PATH에 claude를 추가하세요.\n${e.message}',
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

  static Future<ClaudeProcessResult> _defaultRunner(
    String executable,
    List<String> arguments, {
    String? stdinText,
    Duration? timeout,
  }) async {
    final process = await Process.start(executable, arguments);

    // Feed stdin then close it. The process may close its stdin reader early
    // (e.g. on error); swallow the resulting broken-pipe error.
    try {
      if (stdinText != null && stdinText.isNotEmpty) {
        process.stdin.write(stdinText);
      }
      await process.stdin.close();
    } catch (_) {
      // ignore broken-pipe style failures.
    }

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    Future<int> exitFuture = process.exitCode;
    if (timeout != null) {
      exitFuture = exitFuture.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          throw TimeoutException('Claude Code process timed out', timeout);
        },
      );
    }

    final exitCode = await exitFuture;
    final out = await stdoutFuture;
    final err = await stderrFuture;
    return ClaudeProcessResult(exitCode: exitCode, stdout: out, stderr: err);
  }
}
