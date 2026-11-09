import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ApiException implements Exception {
  ApiException(this.code, {this.statusCode});
  final String code;
  final int? statusCode;
}

class Api {
  /// Production by default; local builds can pass
  /// `--dart-define=API_BASE_URL=http://localhost:4000`.
  Api({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api-dropit.yarinlevi.dev',
    ),
  });

  final String baseUrl;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? token;

  /// Last successful GET response per path. Screens seed their state from it so
  /// switching tabs shows data instantly while a fresh copy loads behind it.
  final Map<String, Map<String, dynamic>> _cache = {};

  Map<String, dynamic>? peek(String path) => _cache[path];

  void clearCache() => _cache.clear();

  Future<File> _sessionFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/session.json');
  }

  Future<File> _themeFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/theme.json');
  }

  /// Returns 'system' | 'light' | 'dark'. Stored outside the session file so it
  /// survives logout.
  Future<String> loadThemeMode() async {
    try {
      final file = await _themeFile();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final mode = data['mode'];
        if (mode == 'light' || mode == 'dark' || mode == 'system') return mode as String;
      }
    } catch (_) {}
    return 'system';
  }

  Future<void> saveThemeMode(String mode) async {
    try {
      final file = await _themeFile();
      await file.writeAsString(jsonEncode({'mode': mode}), flush: true);
    } catch (_) {}
  }

  Future<File> _langFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/language.json');
  }

  /// Language picked while signed out ('en' | 'he'), or null. The account's
  /// language wins once signed in.
  Future<String?> loadLanguage() async {
    try {
      final file = await _langFile();
      if (await file.exists()) {
        final lang = (jsonDecode(await file.readAsString()) as Map)['lang'];
        if (lang == 'en' || lang == 'he') return lang as String;
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveLanguage(String lang) async {
    try {
      final file = await _langFile();
      await file.writeAsString(jsonEncode({'lang': lang}), flush: true);
    } catch (_) {}
  }

  Future<void> loadToken() async {
    try {
      token = await _storage.read(key: 'token');
    } catch (_) {
      token = null;
    }
    if (token == null || token!.isEmpty) {
      try {
        final file = await _sessionFile();
        if (await file.exists()) {
          final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          final savedToken = data['token'] as String?;
          if (savedToken != null && savedToken.isNotEmpty) {
            token = savedToken;
          }
        }
      } catch (_) {}
    }
  }

  Future<void> setToken(String? value) async {
    token = value;
    // Login, logout and session expiry change whose data the cache holds.
    clearCache();
    try {
      if (value == null) {
        await _storage.delete(key: 'token');
      } else {
        await _storage.write(key: 'token', value: value);
      }
    } catch (_) {}
    try {
      final file = await _sessionFile();
      if (value == null) {
        if (await file.exists()) await file.delete();
      } else {
        Map<String, dynamic> existing = {};
        if (await file.exists()) {
          try {
            existing = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          } catch (_) {}
        }
        existing['token'] = value;
        await file.writeAsString(jsonEncode(existing), flush: true);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadCachedMe() async {
    try {
      final file = await _sessionFile();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final me = data['me'];
      if (me is Map) return me.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  Future<void> saveCachedMe(Map<String, dynamic>? me) async {
    try {
      final file = await _sessionFile();
      Map<String, dynamic> existing = {};
      if (await file.exists()) {
        try {
          existing = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        } catch (_) {}
      }
      if (me == null) {
        existing.remove('me');
      } else {
        existing['me'] = me;
      }
      if (token != null) existing['token'] = token;
      await file.writeAsString(jsonEncode(existing), flush: true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> send(String method, String path, {Object? body}) async {
    final response = http.Request(method, Uri.parse('$baseUrl$path'));
    if (token != null) response.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      response.headers['content-type'] = 'application/json';
      response.body = jsonEncode(body);
    }
    final sent = await response.send();
    final text = await sent.stream.bytesToString();
    final data = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    if (sent.statusCode >= 400) {
      throw ApiException(data['error'] as String? ?? 'server_error', statusCode: sent.statusCode);
    }
    if (method.toUpperCase() == 'GET') _cache[path] = data;
    return data;
  }
}
