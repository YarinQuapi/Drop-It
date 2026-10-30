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
  Api({this.baseUrl = 'https://api-dropit.yarinlevi.dev'});

  final String baseUrl;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? token;

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
    return data;
  }
}
