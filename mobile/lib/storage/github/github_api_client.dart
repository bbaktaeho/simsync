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
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'content': base64.encode(utf8.encode(content)),
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
}
