import 'dart:async';
import 'dart:io';

import 'cli_process.dart';

/// Raised when the Codex CLI cannot be run or returns an error. The [message]
/// is safe to surface directly to the user.
class CodexCliException implements Exception {
  CodexCliException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin wrapper around the OpenAI Codex CLI headless mode (`codex exec`).
///
/// Mirrors [ClaudeCodeService]'s pipe pattern: the instruction is the
/// positional prompt and the notes are streamed via stdin — `codex exec`
/// appends piped stdin to the prompt as a `<stdin>` block (no ARG_MAX limit).
/// Codex has no per-tool deny flags, so isolation relies on the read-only
/// sandbox plus the empty temp working directory from [runCliProcess].
/// The model is always the CLI's own default — Anthropic model ids from the
/// settings are meaningless to Codex.
class CodexCliService {
  CodexCliService({CliProcessRunner? runner}) : _run = runner ?? runCliProcess;

  final CliProcessRunner _run;

  /// Codex runs reasoning models that can be slow on long contexts — allow
  /// more headroom than the Claude CLI's 180s.
  static const Duration summaryTimeout = Duration(seconds: 300);
  static const Duration versionTimeout = Duration(seconds: 10);

  /// Upper bound on the piped notes context. Keeps latency, cost and memory
  /// bounded even when a period holds an unusually large amount of text.
  static const int maxContextChars = 200000;

  String _resolveExecutable(String? cliPath) {
    final trimmed = cliPath?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    // GUI apps launched from Finder do not inherit the shell PATH, so a bare
    // `codex` may not resolve. Probe common install locations first; fall back
    // to `codex` (which works when launched from a shell that has it on PATH).
    final home = Platform.environment['HOME'];
    final candidates = <String>[
      '/opt/homebrew/bin/codex',
      '/usr/local/bin/codex',
      if (home != null) '$home/.local/bin/codex',
      if (home != null) '$home/.npm-global/bin/codex',
      '/usr/bin/codex',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return 'codex';
  }

  /// Whether the Codex CLI is reachable (`codex --version` exits 0). Login
  /// state is deliberately not probed: `codex login status` reports the cached
  /// auth file, not whether the token still works, so auth failures surface at
  /// generation time with Codex's own actionable message.
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

  /// Runs one summary pass. Throws [CodexCliException] with a user-facing
  /// message on any failure (missing CLI, timeout, non-zero exit, empty reply).
  Future<String> summarize({
    required String instruction,
    required String notesContext,
    String? cliPath,
  }) async {
    final exe = _resolveExecutable(cliPath);
    final trimmedInstruction = instruction.trim();
    if (trimmedInstruction.isEmpty) {
      throw CodexCliException('AI 지침이 비어 있습니다. 설정 > AI에서 지침을 입력하세요.');
    }
    if (notesContext.trim().isEmpty) {
      throw CodexCliException('요약할 노트가 없습니다.');
    }

    var context = notesContext;
    if (context.length > maxContextChars) {
      context = context.substring(0, maxContextChars);
    }

    // `codex exec` streams progress logs to stdout; only the file written by
    // --output-last-message carries the final agent message.
    final outDir = await Directory.systemTemp.createTemp('simsync_codex_');
    final outFile = File('${outDir.path}/last_message.md');
    try {
      final args = <String>[
        'exec',
        // Model-run shell commands may read but never write or use the network.
        '--sandbox',
        'read-only',
        // The isolated temp working directory is not a git repository.
        '--skip-git-repo-check',
        // One-off run — don't leave a resumable session on disk.
        '--ephemeral',
        '--color',
        'never',
        '--output-last-message',
        outFile.path,
        trimmedInstruction,
      ];

      final CliProcessResult result;
      try {
        result = await _run(
          exe,
          args,
          stdinText: context,
          timeout: summaryTimeout,
        );
      } on ProcessException catch (e) {
        throw CodexCliException(
          'Codex CLI 실행 파일을 찾을 수 없습니다 ($exe).\n'
          '설정 > AI에서 CLI 경로를 지정하거나 PATH에 codex를 추가하세요.\n${e.message}',
        );
      } on TimeoutException {
        throw CodexCliException('Codex 응답이 시간 초과되었습니다 (${summaryTimeout.inSeconds}s).');
      }

      if (result.exitCode != 0) {
        final detail = result.stderr.trim().isNotEmpty
            ? result.stderr.trim()
            : result.stdout.trim();
        throw CodexCliException('Codex 오류 (exit ${result.exitCode}).\n$detail');
      }

      final output =
          await outFile.exists() ? (await outFile.readAsString()).trim() : '';
      if (output.isEmpty) {
        throw CodexCliException('Codex가 빈 응답을 반환했습니다.');
      }
      return output;
    } finally {
      try {
        await outDir.delete(recursive: true);
      } catch (_) {
        // best-effort cleanup
      }
    }
  }
}
