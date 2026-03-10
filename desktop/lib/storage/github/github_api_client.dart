import 'dart:convert';

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

  /// Closes the underlying HTTP client.
  void dispose() {
    _httpClient.close();
  }
}
