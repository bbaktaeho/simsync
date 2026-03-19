import 'dart:convert';
import 'dart:io';

class GitService {
  final String repoUrl;
  final String localPath;
  final String token;
  final String? userName;
  final String? userEmail;

  GitService({
    required this.repoUrl,
    required this.localPath,
    required this.token,
    this.userName,
    this.userEmail,
  });

  factory GitService.fromRepo({
    required String owner,
    required String repo,
    required String token,
    String? userName,
    String? userEmail,
  }) {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    return GitService(
      repoUrl: 'https://github.com/$owner/$repo.git',
      localPath: '$home/.simsync/git/$owner/$repo',
      token: token,
      userName: userName,
      userEmail: userEmail,
    );
  }

  bool isCloned() {
    final gitDir = Directory('$localPath/.git');
    return gitDir.existsSync();
  }

  Future<bool> cloneIfNeeded() async {
    if (isCloned()) {
      await _configureCredential();
      return true;
    }

    if (!await _isGitAvailable()) {
      stderr.writeln('[GitService] git binary not found; skipping clone');
      return false;
    }

    try {
      await Directory(localPath).create(recursive: true);
      final result = await Process.run(
        'git',
        ['clone', repoUrl, localPath],
        environment: _authEnv,
      );
      if (result.exitCode != 0) {
        stderr.writeln('[GitService] clone failed: ${_sanitize(result.stderr as String)}');
        return false;
      }
      await _configureCredential();
      return true;
    } catch (e) {
      stderr.writeln('[GitService] clone error: ${_sanitize(e.toString())}');
      return false;
    }
  }

  Future<bool> add(String relativePath) async {
    if (!isCloned()) return false;
    try {
      final result = await Process.run(
        'git',
        ['-C', localPath, 'add', relativePath],
      );
      if (result.exitCode != 0) {
        stderr.writeln('[GitService] add failed: ${_sanitize(result.stderr as String)}');
        return false;
      }
      return true;
    } catch (e) {
      stderr.writeln('[GitService] add error: ${_sanitize(e.toString())}');
      return false;
    }
  }

  Future<bool> addAll() async {
    if (!isCloned()) return false;
    try {
      final result = await Process.run(
        'git',
        ['-C', localPath, 'add', '-A'],
      );
      if (result.exitCode != 0) {
        stderr.writeln('[GitService] addAll failed: ${_sanitize(result.stderr as String)}');
        return false;
      }
      return true;
    } catch (e) {
      stderr.writeln('[GitService] addAll error: ${_sanitize(e.toString())}');
      return false;
    }
  }

  Future<bool> commit(String message) async {
    if (!isCloned()) return false;
    try {
      final result = await Process.run(
        'git',
        ['-C', localPath, 'commit', '-m', message],
      );
      if (result.exitCode != 0) {
        final stderrStr = result.stderr as String;
        if (stderrStr.isEmpty && (result.stdout as String).contains('nothing to commit')) {
          return true;
        }
        stderr.writeln('[GitService] commit failed: ${_sanitize(stderrStr)}');
        return false;
      }
      return true;
    } catch (e) {
      stderr.writeln('[GitService] commit error: ${_sanitize(e.toString())}');
      return false;
    }
  }

  Future<bool> push() async {
    if (!isCloned()) return false;
    try {
      final result = await Process.run(
        'git',
        ['-C', localPath, 'push'],
        environment: _authEnv,
      );
      if (result.exitCode != 0) {
        stderr.writeln('[GitService] push failed: ${_sanitize(result.stderr as String)}');
        return false;
      }
      return true;
    } catch (e) {
      stderr.writeln('[GitService] push error: ${_sanitize(e.toString())}');
      return false;
    }
  }

  Future<bool> addCommitPush(String relativePath, String message) async {
    if (!await add(relativePath)) return false;
    if (!await commit(message)) return false;
    return push();
  }

  Future<bool> addAllCommitPush(String message) async {
    if (!await addAll()) return false;
    if (!await commit(message)) return false;
    return push();
  }

  Future<bool> pull() async {
    if (!isCloned()) return false;

    if (!await _isGitAvailable()) {
      stderr.writeln('[GitService] git binary not found; skipping pull');
      return false;
    }

    try {
      final result = await Process.run(
        'git',
        ['-C', localPath, 'pull', '--ff-only'],
        environment: _authEnv,
      );
      if (result.exitCode != 0) {
        stderr.writeln('[GitService] pull failed: ${_sanitize(result.stderr as String)}');
        return false;
      }
      return true;
    } catch (e) {
      stderr.writeln('[GitService] pull error: ${_sanitize(e.toString())}');
      return false;
    }
  }

  Map<String, String> get _authEnv => {
        'GIT_ASKPASS': 'echo',
        'GIT_TERMINAL_PROMPT': '0',
        ...Platform.environment,
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'http.https://github.com/.extraheader',
        'GIT_CONFIG_VALUE_0': 'Authorization: Basic $_base64Token',
      };

  String get _base64Token {
    return base64Encode(utf8.encode('x-access-token:$token'));
  }

  Future<void> _configureCredential() async {
    try {
      await Process.run('git', [
        '-C', localPath, 'remote', 'set-url', 'origin', repoUrl,
      ]);
      if (userName != null && userName!.isNotEmpty) {
        await Process.run('git', [
          '-C', localPath, 'config', 'user.name', userName!,
        ]);
      }
      if (userEmail != null && userEmail!.isNotEmpty) {
        await Process.run('git', [
          '-C', localPath, 'config', 'user.email', userEmail!,
        ]);
      }
    } catch (_) {}
  }

  String _sanitize(String message) {
    return message.replaceAll(token, '***');
  }

  Future<bool> _isGitAvailable() async {
    try {
      final result = await Process.run('git', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
