import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/claude_code_service.dart';

void main() {
  group('ClaudeCodeService.summarizeWeek', () {
    test('invokes claude --print with instruction as prompt and notes on stdin',
        () async {
      String? capturedExe;
      List<String>? capturedArgs;
      String? capturedStdin;

      final service = ClaudeCodeService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          capturedExe = executable;
          capturedArgs = arguments;
          capturedStdin = stdinText;
          return const ClaudeProcessResult(
            exitCode: 0,
            stdout: '  weekly summary  ',
            stderr: '',
          );
        },
      );

      final result = await service.summarizeWeek(
        instruction: 'Summarize the week',
        notesContext: '# 2026-06-15\nDid stuff',
      );

      expect(result, 'weekly summary'); // trimmed
      // With no configured path, the resolver uses `claude` or a detected
      // absolute install path ending in `/claude`.
      expect(capturedExe == 'claude' || capturedExe!.endsWith('/claude'), isTrue);
      expect(capturedArgs, contains('--print'));
      expect(capturedArgs, containsAllInOrder(['--output-format', 'text']));
      // Instruction is the positional prompt (last arg).
      expect(capturedArgs!.last, 'Summarize the week');
      // Notes are piped via stdin.
      expect(capturedStdin, '# 2026-06-15\nDid stuff');
    });

    test('uses configured cli path and model when provided', () async {
      List<String>? capturedArgs;
      String? capturedExe;

      final service = ClaudeCodeService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          capturedExe = executable;
          capturedArgs = arguments;
          return const ClaudeProcessResult(
            exitCode: 0,
            stdout: 'ok',
            stderr: '',
          );
        },
      );

      await service.summarizeWeek(
        instruction: 'go',
        notesContext: 'notes',
        cliPath: '/opt/homebrew/bin/claude',
        model: 'sonnet',
      );

      expect(capturedExe, '/opt/homebrew/bin/claude');
      expect(capturedArgs, containsAllInOrder(['--model', 'sonnet']));
    });

    test('throws a friendly error on non-zero exit', () async {
      final service = ClaudeCodeService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          return const ClaudeProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'boom',
          );
        },
      );

      expect(
        () => service.summarizeWeek(instruction: 'x', notesContext: 'y'),
        throwsA(isA<ClaudeCodeException>()),
      );
    });

    test('throws when the cli is missing (ProcessException)', () async {
      final service = ClaudeCodeService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          throw const ProcessException('claude', [], 'not found', 2);
        },
      );

      await expectLater(
        service.summarizeWeek(instruction: 'x', notesContext: 'y'),
        throwsA(
          isA<ClaudeCodeException>().having(
            (e) => e.message,
            'message',
            contains('찾을 수 없습니다'),
          ),
        ),
      );
    });

    test('throws when there are no notes to summarize', () async {
      final service = ClaudeCodeService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          fail('runner should not be called when context is empty');
        },
      );

      await expectLater(
        service.summarizeWeek(instruction: 'x', notesContext: '   '),
        throwsA(isA<ClaudeCodeException>()),
      );
    });

    test('throws on empty output', () async {
      final service = ClaudeCodeService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          return const ClaudeProcessResult(
            exitCode: 0,
            stdout: '   ',
            stderr: '',
          );
        },
      );

      await expectLater(
        service.summarizeWeek(instruction: 'x', notesContext: 'y'),
        throwsA(isA<ClaudeCodeException>()),
      );
    });
  });

  group('ClaudeCodeService.isAvailable', () {
    test('true when version check exits 0', () async {
      final service = ClaudeCodeService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          expect(arguments, ['--version']);
          return const ClaudeProcessResult(
            exitCode: 0,
            stdout: '1.0.0',
            stderr: '',
          );
        },
      );
      expect(await service.isAvailable(), isTrue);
    });

    test('false when the runner throws', () async {
      final service = ClaudeCodeService(
        runner: (executable, arguments, {stdinText, timeout}) async {
          throw const ProcessException('claude', []);
        },
      );
      expect(await service.isAvailable(), isFalse);
    });
  });

  group('ClaudeCodeService.buildPathEnv', () {
    test('prepends the executable directory so the node shebang resolves', () {
      final path = ClaudeCodeService.buildPathEnv(
        '/opt/homebrew/bin/claude',
        '/usr/bin:/bin',
        '/Users/x',
      );
      final dirs = path.split(':');
      // The executable's own directory (where a co-installed node lives) comes
      // first, ahead of the minimal inherited PATH.
      expect(dirs.first, '/opt/homebrew/bin');
      expect(dirs.indexOf('/opt/homebrew/bin'), lessThan(dirs.indexOf('/usr/bin')));
    });

    test('includes common install dirs and the inherited PATH, de-duplicated', () {
      final path = ClaudeCodeService.buildPathEnv(
        '/usr/local/bin/claude',
        '/usr/local/bin:/usr/bin', // /usr/local/bin already present
        '/Users/x',
      );
      final dirs = path.split(':');
      expect(dirs, contains('/opt/homebrew/bin'));
      expect(dirs, contains('/Users/x/.local/bin'));
      expect(dirs, contains('/usr/bin'));
      // No duplicates even though /usr/local/bin appears in both lists.
      expect(dirs.where((d) => d == '/usr/local/bin').length, 1);
    });

    test('tolerates a bare executable name and a null PATH', () {
      final path = ClaudeCodeService.buildPathEnv('claude', null, null);
      final dirs = path.split(':');
      expect(dirs, contains('/opt/homebrew/bin'));
      expect(dirs, isNot(contains(''))); // no empty segments
    });
  });
}
