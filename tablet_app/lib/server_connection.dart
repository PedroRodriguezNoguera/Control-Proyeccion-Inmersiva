import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'config_service.dart';

/// Singleton TCP connection shared across all screens.
/// Fire-and-forget commands go through [send]; it auto-reconnects on failure.
class ServerConnection {
  ServerConnection._();
  static final ServerConnection instance = ServerConnection._();

  Socket? _socket;
  Completer<void>? _connectingCompleter;
  // Serializes all writes: each send() runs after the previous one completes,
  // preventing concurrent flush() calls that cause "StreamSink is bound to a stream".
  Future<void> _sendChain = Future.value();

  Future<void> _ensureConnected() async {
    if (_socket != null) return;

    if (_connectingCompleter != null) {
      await _connectingCompleter!.future;
      return;
    }

    _connectingCompleter = Completer<void>();
    try {
      _socket = await Socket.connect(
        ConfigService.serverIp,
        ConfigService.serverPort,
        timeout: const Duration(seconds: 5),
      );
      _socket!.listen(
        (data) => debugPrint('Server: ${String.fromCharCodes(data)}'),
        onError: (e) {
          debugPrint('ServerConnection error: $e');
          _socket?.destroy();
          _socket = null;
        },
        onDone: () => _socket = null,
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('ServerConnection connect failed: $e');
      _socket = null;
    } finally {
      _connectingCompleter!.complete();
      _connectingCompleter = null;
    }
  }

  Future<void> send(String message) {
    _sendChain = _sendChain
        .then((_) => _doSend(message))
        .catchError((_) {});
    return _sendChain;
  }

  Future<void> _doSend(String message) async {
    await _ensureConnected();
    if (_socket == null) {
      debugPrint('ServerConnection: offline, dropping: $message');
      return;
    }
    try {
      _socket!.writeln(message);
      await _socket!.flush();
    } catch (e) {
      debugPrint('ServerConnection send failed: $e');
      _socket?.destroy();
      _socket = null;
    }
  }

  /// Call when the server IP changes so the next [send] reconnects.
  void reset() {
    _socket?.destroy();
    _socket = null;
    _sendChain = Future.value();
  }
}
