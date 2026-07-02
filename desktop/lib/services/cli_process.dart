import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Captured result of a single CLI invocation.
class CliProcessResult {
  const CliProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs an external process, optionally feeding [stdinText], and returns the
/// captured result. Injectable so the CLI services ([ClaudeCodeService],
/// [CodexCliService]) are unit-testable without the real binaries installed.
typedef CliProcessRunner = Future<CliProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? stdinText,
  Duration? timeout,
});

/// Builds a PATH for spawning [executable] that survives a Finder launch.
///
/// A CLI may be a `#!/usr/bin/env node` script (claude), so executing it needs
/// its interpreter on PATH — but a GUI app launched from Finder inherits only a
/// minimal PATH (`/usr/bin:/bin:...`) without Homebrew/npm dirs. We prepend the
/// executable's own directory (where a co-installed interpreter usually lives)
/// and the common install locations, then the inherited PATH, de-duplicated.
String buildCliPathEnv(String executable, String? currentPath, String? home) {
  final dirs = <String>[
    if (executable.contains('/'))
      executable.substring(0, executable.lastIndexOf('/')),
    '/opt/homebrew/bin',
    '/usr/local/bin',
    if (home != null) '$home/.local/bin',
    if (home != null) '$home/.claude/local',
    '/usr/bin',
    '/bin',
  ];
  final inherited = (currentPath ?? '').split(':');
  final seen = <String>{};
  final ordered = <String>[];
  for (final dir in [...dirs, ...inherited]) {
    if (dir.isNotEmpty && seen.add(dir)) ordered.add(dir);
  }
  return ordered.join(':');
}

/// Default [CliProcessRunner]: spawns the process in a throwaway empty temp
/// directory so the agent CLI sees an isolated workspace — no project
/// instruction files (CLAUDE.md / AGENTS.md), no local files to wander into,
/// and no workspace-trust prompt blocking a headless run.
Future<CliProcessResult> runCliProcess(
  String executable,
  List<String> arguments, {
  String? stdinText,
  Duration? timeout,
}) async {
  final workDir = await Directory.systemTemp.createTemp('simsync_ai_');
  try {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workDir.path,
      environment: {
        'PATH': buildCliPathEnv(
          executable,
          Platform.environment['PATH'],
          Platform.environment['HOME'],
        ),
      },
    );

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
          throw TimeoutException('CLI process timed out', timeout);
        },
      );
    }

    final exitCode = await exitFuture;
    final out = await stdoutFuture;
    final err = await stderrFuture;
    return CliProcessResult(exitCode: exitCode, stdout: out, stderr: err);
  } finally {
    try {
      await workDir.delete(recursive: true);
    } catch (_) {
      // best-effort cleanup
    }
  }
}
