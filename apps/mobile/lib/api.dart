import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.code);
  final String code;
}

class Api {
  Api({this.baseUrl = 'http://127.0.0.1:4000'});

  final String baseUrl;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? token;

  Future<void> loadToken() async {
    token = await _storage.read(key: 'token');
  }

  Future<void> setToken(String? value) async {
    token = value;
    if (value == null) {
      await _storage.delete(key: 'token');
    } else {
      await _storage.write(key: 'token', value: value);
    }
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
      throw ApiException(data['error'] as String? ?? 'server_error');
    }
    return data;
  }
}
