import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

// --- Models ---

class GitHubFile {
  final String name;
  final String path;
  final String sha;
  final String? content;
  final String type;

  GitHubFile({
    required this.name,
    required this.path,
    required this.sha,
    this.content,
    required this.type,
  });

  factory GitHubFile.fromJson(Map<String, dynamic> json) {
    return GitHubFile(
      name: json['name'] as String,
      path: json['path'] as String,
      sha: json['sha'] as String,
      content: json['content'] as String?,
      type: json['type'] as String,
    );
  }

  /// Decodes Base64 content returned by GitHub (which includes newlines).
  String? get decodedContent {
    if (content == null) return null;
    final cleaned = content!.replaceAll('\n', '');
    return utf8.decode(base64.decode(cleaned));
  }
}

/// One entry in a recursive Git tree listing.
class GitHubTreeEntry {
  final String path;
  final String sha;
  final String type; // 'blob' or 'tree'
  final int? size;

  GitHubTreeEntry({
    required this.path,
    required this.sha,
    required this.type,
    this.size,
  });
}

/// Result of a recursive tree fetch. [truncated] = true means GitHub did not
/// return the full tree (very large repos). Callers must fall back to the
/// legacy directory-listing path in that case.
class GitHubTreeResult {
  final List<GitHubTreeEntry> entries;
  final bool truncated;

  GitHubTreeResult({required this.entries, required this.truncated});
}

/// [GitHubApiClient.commitFiles]가 커밋할 파일 하나.
/// [mode]는 '100644'(일반 파일) 또는 '120000'(symlink — content가 링크 대상 경로).
typedef CommitFileEntry = ({String path, String content, String mode});

// --- Exceptions ---

class GitHubApiException implements Exception {
  final int statusCode;
  final String body;

  GitHubApiException(this.statusCode, this.body);

  @override
  String toString() => 'GitHubApiException($statusCode): $body';
}

class GitHubNotFoundException implements Exception {
  final String path;

  GitHubNotFoundException(this.path);

  @override
  String toString() => 'GitHubNotFoundException: $path';
}

class GitHubConflictException implements Exception {
  final String path;

  GitHubConflictException(this.path);

  @override
  String toString() => 'GitHubConflictException: $path';
}

// --- Client ---

class GitHubApiClient {
  static const String _baseUrl = 'https://api.github.com';

  final String _token;
  final String _owner;
  final String _repo;
  final http.Client _httpClient;

  GitHubApiClient({
    required String token,
    required String owner,
    required String repo,
    http.Client? httpClient,
  })  : _token = token,
        _owner = owner,
        _repo = repo,
        _httpClient = httpClient ?? http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github.v3+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Uri _contentsUri(String path) =>
      Uri.parse('$_baseUrl/repos/$_owner/$_repo/contents/$path');

  /// Fetches a single file. Throws [GitHubNotFoundException] on 404.
  Future<GitHubFile> getFile(String path) async {
    final response = await _httpClient.get(
      _contentsUri(path),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      throw GitHubNotFoundException(path);
    }

    if (response.statusCode != 200) {
      throw GitHubApiException(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return GitHubFile.fromJson(json);
  }

  /// Lists files in a directory. Returns empty list on 404.
  Future<List<GitHubFile>> listDirectory(String path) async {
    final response = await _httpClient.get(
      _contentsUri(path),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      return [];
    }

    if (response.statusCode != 200) {
      throw GitHubApiException(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as List<dynamic>;
    return json
        .map((item) => GitHubFile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Creates or updates a file. Returns the new SHA.
  /// Pass [sha] to update an existing file; omit for creation.
  /// Throws [GitHubConflictException] on 409.
  Future<String> putFile({
    required String path,
    required String content,
    required String message,
    String? sha,
  }) {
    return putBinaryFile(
      path: path,
      bytes: Uint8List.fromList(utf8.encode(content)),
      message: message,
      sha: sha,
    );
  }

  /// Creates or updates a binary file (raw bytes, base64-encoded directly —
  /// no utf8 round-trip, so images survive intact). Returns the new SHA.
  Future<String> putBinaryFile({
    required String path,
    required Uint8List bytes,
    required String message,
    String? sha,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'content': base64.encode(bytes),
    };
    if (sha != null) {
      body['sha'] = sha;
    }

    final response = await _httpClient.put(
      _contentsUri(path),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 409) {
      throw GitHubConflictException(path);
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw GitHubApiException(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final contentMap = json['content'] as Map<String, dynamic>;
    return contentMap['sha'] as String;
  }

  /// Fetches a file's raw bytes via the raw media type. Works past the 1MB
  /// base64 limit of the JSON contents response. Throws
  /// [GitHubNotFoundException] on 404.
  Future<Uint8List> getRawFile(String path) async {
    final response = await _httpClient.get(
      _contentsUri(path),
      headers: {
        ..._headers,
        'Accept': 'application/vnd.github.raw+json',
      },
    );

    if (response.statusCode == 404) {
      throw GitHubNotFoundException(path);
    }

    if (response.statusCode != 200) {
      throw GitHubApiException(response.statusCode, response.body);
    }

    return response.bodyBytes;
  }

  /// Deletes a file. Uses [http.Request] to send a DELETE with a body.
  Future<void> deleteFile({
    required String path,
    required String sha,
    required String message,
  }) async {
    final request = http.Request('DELETE', _contentsUri(path));
    request.headers.addAll({
      ..._headers,
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode({
      'message': message,
      'sha': sha,
    });

    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw GitHubApiException(response.statusCode, response.body);
    }
  }

  /// Creates a private repo with auto-init. Returns `full_name`.
  /// Throws [GitHubApiException] with 422 on duplicate name.
  Future<String> createRepo({required String name}) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/user/repos'),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'private': true,
        'auto_init': true,
      }),
    );

    if (response.statusCode == 422) {
      throw GitHubApiException(422, 'Repository already exists');
    }

    if (response.statusCode != 201) {
      throw GitHubApiException(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['full_name'] as String;
  }

  /// Returns the entire repo tree for [branch] in a single recursive call.
  ///
  /// Two HTTP round-trips:
  ///   1. `/repos/{owner}/{repo}/branches/{branch}` → root tree SHA
  ///   2. `/repos/{owner}/{repo}/git/trees/{tree_sha}?recursive=1` → flat list
  ///
  /// Replaces the per-directory `listDirectory` traversal used by the legacy
  /// listing path. If the response is `truncated: true` (very large repos),
  /// callers must fall back to the legacy traversal — partial trees are not
  /// safe to rely on for completeness.
  Future<GitHubTreeResult> listRepoTree({required String branch}) async {
    final branchUri =
        Uri.parse('$_baseUrl/repos/$_owner/$_repo/branches/$branch');
    final branchResp = await _httpClient.get(branchUri, headers: _headers);
    if (branchResp.statusCode != 200) {
      throw GitHubApiException(branchResp.statusCode, branchResp.body);
    }
    final branchJson = jsonDecode(branchResp.body) as Map<String, dynamic>;
    final commit = branchJson['commit'] as Map<String, dynamic>;
    final commitDetail = commit['commit'] as Map<String, dynamic>;
    final tree = commitDetail['tree'] as Map<String, dynamic>;
    final treeSha = tree['sha'] as String;

    final treeUri = Uri.parse(
      '$_baseUrl/repos/$_owner/$_repo/git/trees/$treeSha?recursive=1',
    );
    final treeResp = await _httpClient.get(treeUri, headers: _headers);
    if (treeResp.statusCode != 200) {
      throw GitHubApiException(treeResp.statusCode, treeResp.body);
    }
    final treeJson = jsonDecode(treeResp.body) as Map<String, dynamic>;
    final list = (treeJson['tree'] as List<dynamic>? ?? const []);
    final truncated = treeJson['truncated'] as bool? ?? false;
    final entries = list.map((e) {
      final m = e as Map<String, dynamic>;
      return GitHubTreeEntry(
        path: m['path'] as String,
        sha: m['sha'] as String,
        type: m['type'] as String,
        size: (m['size'] as num?)?.toInt(),
      );
    }).toList();
    return GitHubTreeResult(entries: entries, truncated: truncated);
  }

  /// [files]를 단일 커밋으로 [branch]에 추가/갱신하고 새 커밋 SHA를 돌려준다.
  ///
  /// Contents API 대신 Git Database API(트리 inline content)를 쓰는 이유:
  /// (1) 여러 파일을 커밋 하나로 묶고, (2) mode 120000으로 symlink를 만들 수
  /// 있다 — Contents API는 일반 파일만 만든다.
  ///
  /// ref 갱신은 fast-forward만 시도한다. 사이에 다른 커밋이 끼면(노트 저장
  /// 경합) 422로 실패하며 [GitHubApiException]을 던진다 — 호출자가 재시도를
  /// 판단한다.
  Future<String> commitFiles({
    required String branch,
    required String message,
    required List<CommitFileEntry> files,
  }) async {
    Map<String, dynamic> decode(http.Response r, int expected) {
      if (r.statusCode != expected) {
        throw GitHubApiException(r.statusCode, r.body);
      }
      return jsonDecode(r.body) as Map<String, dynamic>;
    }

    final jsonHeaders = {..._headers, 'Content-Type': 'application/json'};

    // 1. branch HEAD 커밋/트리 SHA 조회.
    final branchJson = decode(
      await _httpClient.get(
        Uri.parse('$_baseUrl/repos/$_owner/$_repo/branches/$branch'),
        headers: _headers,
      ),
      200,
    );
    final commit = branchJson['commit'] as Map<String, dynamic>;
    final headSha = commit['sha'] as String;
    final baseTreeSha = ((commit['commit'] as Map<String, dynamic>)['tree']
        as Map<String, dynamic>)['sha'] as String;

    // 2. base_tree 위에 파일들을 얹은 새 트리.
    final treeJson = decode(
      await _httpClient.post(
        Uri.parse('$_baseUrl/repos/$_owner/$_repo/git/trees'),
        headers: jsonHeaders,
        body: jsonEncode({
          'base_tree': baseTreeSha,
          'tree': [
            for (final f in files)
              {'path': f.path, 'mode': f.mode, 'type': 'blob', 'content': f.content},
          ],
        }),
      ),
      201,
    );

    // 3. 커밋 생성.
    final commitJson = decode(
      await _httpClient.post(
        Uri.parse('$_baseUrl/repos/$_owner/$_repo/git/commits'),
        headers: jsonHeaders,
        body: jsonEncode({
          'message': message,
          'tree': treeJson['sha'] as String,
          'parents': [headSha],
        }),
      ),
      201,
    );
    final newCommitSha = commitJson['sha'] as String;

    // 4. branch ref를 새 커밋으로 이동 (fast-forward).
    decode(
      await _httpClient.patch(
        Uri.parse('$_baseUrl/repos/$_owner/$_repo/git/refs/heads/$branch'),
        headers: jsonHeaders,
        body: jsonEncode({'sha': newCommitSha}),
      ),
      200,
    );
    return newCommitSha;
  }

  /// Checks whether a repo exists. Returns true on 200, false on 404.
  Future<bool> repoExists({
    required String owner,
    required String repo,
  }) async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/repos/$owner/$repo'),
      headers: _headers,
    );

    if (response.statusCode == 200) return true;
    if (response.statusCode == 404) return false;

    throw GitHubApiException(response.statusCode, response.body);
  }

  /// Closes the underlying HTTP client.
  void dispose() {
    _httpClient.close();
  }
}
