import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/cli_process.dart';
import 'package:simsync/services/codex_cli_service.dart';

/// Writes [message] to the `--output-last-message` file named in [arguments],
/// mimicking what `codex exec` does on success.
Future<void> writeLastMessage(List<String> arguments, String message) async {
  final outIdx = arguments.indexOf('--output-last-message');
  expect(outIdx, isNot(-1), reason: 'missing --output-last-message flag');
  await File(arguments[outIdx + 1]).writeAsString(message);
}

void main() {
  group('CodexCliService.summarize', () {
    test('invokes codex exec with instruction as prompt and notes on stdin',
        () async {
      String? capturedExe;
      List<String>? capturedArgs;
      String? capturedStdin;

      final service = CodexCliService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          capturedExe = executable;
          capturedArgs = arguments;
          capturedStdin = stdinText;
          await writeLastMessage(arguments, '  weekly summary  ');
          return const CliProcessResult(
            exitCode: 0,
            stdout: 'progress log noise',
            stderr: '',
          );
        },
      );

      final result = await service.summarize(
        instruction: 'Summarize the week',
        notesContext: '# 2026-06-15\nDid stuff',
      );

      // Trimmed content of the output file — NOT the stdout progress noise.
      expect(result, 'weekly summary');
      // With no configured path, the resolver uses `codex` or a detected
      // absolute install path ending in `/codex`.
      expect(capturedExe == 'codex' || capturedExe!.endsWith('/codex'), isTrue);
      expect(capturedArgs!.first, 'exec');
      // Model-run commands are sandboxed read-only; the temp workdir is not a
      // git repo; no resumable session is left on disk.
      expect(capturedArgs, containsAllInOrder(['--sandbox', 'read-only']));
      expect(capturedArgs, contains('--skip-git-repo-check'));
      expect(capturedArgs, contains('--ephemeral'));
      // Instruction is the positional prompt (last arg); the notes are piped
      // via stdin and codex appends them to the prompt as a <stdin> block.
      expect(capturedArgs!.last, 'Summarize the week');
      expect(capturedStdin, '# 2026-06-15\nDid stuff');
    });

    test('uses configured cli path when provided', () async {
      String? capturedExe;

      final service = CodexCliService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          capturedExe = executable;
          await writeLastMessage(arguments, 'ok');
          return const CliProcessResult(exitCode: 0, stdout: '', stderr: '');
        },
      );

      await service.summarize(
        instruction: 'go',
        notesContext: 'notes',
        cliPath: '/opt/homebrew/bin/codex',
      );

      expect(capturedExe, '/opt/homebrew/bin/codex');
    });

    test('throws on empty output file even when stdout has content', () async {
      final service = CodexCliService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          // Exit 0 but the last-message file is never written (or empty):
          // stdout progress logs must not be mistaken for the result.
          return const CliProcessResult(
            exitCode: 0,
            stdout: 'lots of progress logs',
            stderr: '',
          );
        },
      );

      await expectLater(
        service.summarize(instruction: 'x', notesContext: 'y'),
        throwsA(isA<CodexCliException>()),
      );
    });

    test('throws a friendly error with detail on non-zero exit', () async {
      final service = CodexCliService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          return const CliProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'Please log out and sign in again.',
          );
        },
      );

      await expectLater(
        service.summarize(instruction: 'x', notesContext: 'y'),
        throwsA(
          isA<CodexCliException>().having(
            (e) => e.message,
            'message',
            contains('log out and sign in again'),
          ),
        ),
      );
    });

    test('throws when the cli is missing (ProcessException)', () async {
      final service = CodexCliService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          throw const ProcessException('codex', [], 'not found', 2);
        },
      );

      await expectLater(
        service.summarize(instruction: 'x', notesContext: 'y'),
        throwsA(
          isA<CodexCliException>().having(
            (e) => e.message,
            'message',
            contains('찾을 수 없습니다'),
          ),
        ),
      );
    });

    test('throws when there are no notes to summarize', () async {
      final service = CodexCliService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          fail('runner should not be called when context is empty');
        },
      );

      await expectLater(
        service.summarize(instruction: 'x', notesContext: '   '),
        throwsA(isA<CodexCliException>()),
      );
    });

    test('throws when the instruction is empty', () async {
      final service = CodexCliService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          fail('runner should not be called when the instruction is empty');
        },
      );

      await expectLater(
        service.summarize(instruction: '  ', notesContext: 'notes'),
        throwsA(isA<CodexCliException>()),
      );
    });
  });

  group('CodexCliService.isAvailable', () {
    test('true when version check exits 0', () async {
      final service = CodexCliService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          expect(arguments, ['--version']);
          return const CliProcessResult(
            exitCode: 0,
            stdout: 'codex-cli 0.142.5',
            stderr: '',
          );
        },
      );
      expect(await service.isAvailable(), isTrue);
    });

    test('false when the runner throws', () async {
      final service = CodexCliService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          throw const ProcessException('codex', []);
        },
      );
      expect(await service.isAvailable(), isFalse);
    });
  });
}
