import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ConfigService {
  static late Box _box;

  static const String _defaultPassword = '000000';

  static Future<void> init() async {
    _box = await Hive.openBox('config');
    await _migrateAdminPassword();
  }

  /// On first launch, store the default password as a SHA-256 hash.
  static Future<void> _migrateAdminPassword() async {
    if (!_box.containsKey('admin_hash')) {
      await _box.put('admin_hash', _hash(_defaultPassword));
    }
  }

  static String _hash(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static const int serverPort = 7171;

  static String get serverIp => _box.get('server_ip', defaultValue: '192.168.10.2');

  static Future<void> setServerIp(String ip) async => _box.put('server_ip', ip);

  /// Returns true if [input] matches the stored admin password hash.
  static bool checkAdminPassword(String input) {
    final stored = _box.get('admin_hash');
    return stored != null && _hash(input) == stored;
  }

  /// Replaces the admin password hash. Used from AdminScreen.
  static Future<void> setAdminPassword(String newPassword) async {
    await _box.put('admin_hash', _hash(newPassword));
  }

  /// Orden de los botones "PARED"/"IMÁN" en la pantalla de inicio.
  /// false (por defecto) = Pared a la izquierda, Imán a la derecha.
  /// true = Imán a la izquierda, Pared a la derecha.
  static bool get swapHomeButtons =>
      _box.get('swap_home_buttons', defaultValue: false);

  static Future<void> setSwapHomeButtons(bool value) async =>
      _box.put('swap_home_buttons', value);
}
