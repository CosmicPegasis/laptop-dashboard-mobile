import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../utils/type_coerce.dart';

class ReverseSyncService {
  static const EventChannel _eventChannel = EventChannel(
    'laptop_dashboard_mobile/notification_events',
  );
  static const MethodChannel _methodChannel = MethodChannel(
    'laptop_dashboard_mobile/notification_sync_control',
  );

  StreamSubscription<dynamic>? _subscription;
  final Set<String> _forwardedKeys = {};
  static const int _maxForwardedKeys = 100;
  final Map<String, int> _forwardedContentTimestamps = {};
  static const int _dedupWindowSeconds = 5;

  bool get isSupported => Platform.isAndroid;

  Future<bool> isNotificationAccessEnabled() async {
    if (!isSupported) return false;
    return await _methodChannel.invokeMethod<bool>('isNotificationAccessEnabled') ?? false;
  }

  Future<void> openNotificationAccessSettings() async {
    if (!isSupported) return;
    await _methodChannel.invokeMethod('openNotificationAccessSettings');
  }

  void startListening({
    required Function(Map<String, dynamic>) onEvent,
    required Function(Object) onError,
  }) {
    if (!isSupported || _subscription != null) return;

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final map = Map<String, dynamic>.from(event);
        if (_shouldForward(map)) {
          onEvent(map);
        }
      },
      onError: onError,
    );
  }

  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  bool _shouldForward(Map<String, dynamic> map) {
    final key = map['key']?.toString() ?? '';
    final title = map['title']?.toString() ?? '';
    final text = map['text']?.toString() ?? '';
    final isOngoing = coerceBool(map['is_ongoing']);

    if (title.isEmpty && text.isEmpty) return false;
    if (isOngoing) return false;

    if (key.isNotEmpty && _forwardedKeys.contains(key)) return false;

    final contentKey = '$title|$text';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final lastForwarded = _forwardedContentTimestamps[contentKey];
    if (lastForwarded != null && (now - lastForwarded) < _dedupWindowSeconds) {
      return false;
    }

    if (key.isNotEmpty) {
      _forwardedKeys.add(key);
      if (_forwardedKeys.length > _maxForwardedKeys) {
        _forwardedKeys.remove(_forwardedKeys.first);
      }
    }
    _forwardedContentTimestamps[contentKey] = now;
    _forwardedContentTimestamps.removeWhere(
      (_, timestamp) => (now - timestamp) > _dedupWindowSeconds,
    );

    return true;
  }

}
