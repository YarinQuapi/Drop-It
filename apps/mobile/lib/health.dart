import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';

/// Apple Health bridge. HealthKit only exists on iOS, so every call is a no-op elsewhere.
///
/// Swift (`ios/Runner/HealthSync.swift`) reads samples; this class uploads them with the
/// existing bearer token. Background delivery uploads from Swift using the same token file.
class AppleHealth {
  AppleHealth(this.api);

  static const _channel = MethodChannel('dropit/health');
  static const _chunk = 500;

  /// Bumped after every successful upload so open screens can reload.
  static final ValueNotifier<int> synced = ValueNotifier<int>(0);

  final Api api;

  static bool get supported => Platform.isIOS;

  Future<bool> isAvailable() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system permission sheet, arms background delivery, and runs the first sync.
  /// Returns false when Health is unavailable or the sheet did not finish.
  Future<bool> connect() async {
    if (!await isAvailable()) return false;
    try {
      final done = await _channel.invokeMethod<bool>('requestAuthorization') ?? false;
      if (!done) return false;
      await _channel.invokeMethod('start', {'baseUrl': api.baseUrl});
    } on PlatformException {
      return false;
    }
    return sync();
  }

  /// Stops observers on the phone and tells the server to stop using Health for the food goal.
  Future<void> disconnect() async {
    await stopLocal();
    await api.send('POST', '/api/apple-health/disconnect');
  }

  /// Stops observers and forgets the anchor on this phone without touching the account
  /// (used on logout so a later account is not connected by this phone's uploads).
  static Future<void> stopLocal() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  /// On launch and resume: if the account is connected, re-arm observers and catch up.
  Future<void> syncIfConnected() async {
    if (!supported || api.token == null) return;
    try {
      final state = await api.send('GET', '/api/apple-health');
      if (state['connected'] != true) return;
      await _channel.invokeMethod('start', {'baseUrl': api.baseUrl});
      await sync();
    } catch (_) {}
  }

  /// Reads everything new since the last committed sync and uploads it. A failure leaves the
  /// weight anchor in place, so the next call retries the same samples.
  Future<bool> sync() async {
    if (!supported) return false;
    try {
      final payload = Map<String, dynamic>.from(await _channel.invokeMethod<Map>('readPayload') as Map);
      final weights = (payload['weights'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final deleted = (payload['deletedWeightIds'] as List).cast<String>();
      final days = (payload['days'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      for (var i = 0; i < weights.length; i += _chunk) {
        await _post({'weights': weights.sublist(i, _min(i + _chunk, weights.length))});
      }
      for (var i = 0; i < deleted.length; i += _chunk) {
        await _post({'deletedWeightIds': deleted.sublist(i, _min(i + _chunk, deleted.length))});
      }
      // The last request always carries the days so lastSyncedAt moves even with nothing new.
      await _post({'days': days});

      await _channel.invokeMethod('commit', {'token': payload['token']});
      synced.value++;
      return true;
    } on PlatformException {
      return false;
    } on ApiException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _post(Map<String, dynamic> body) async {
    await api.send('POST', '/api/apple-health/sync', body: {
      'weights': body['weights'] ?? <Object>[],
      'deletedWeightIds': body['deletedWeightIds'] ?? <Object>[],
      'days': body['days'] ?? <Object>[],
    });
  }

  static int _min(int a, int b) => a < b ? a : b;
}
