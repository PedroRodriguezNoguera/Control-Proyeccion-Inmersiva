import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'config_service.dart';

class HdmiService {
  final String servidorIp;

  const HdmiService({required this.servidorIp});

  Future<Map<String, bool>> obtenerEstadoHdmi() async {
    Socket? socket;

    try {
      socket = await Socket.connect(
        servidorIp,
        ConfigService.serverPort,
        timeout: const Duration(seconds: 5),
      );

      socket.writeln('Pro1 status');

      final mensaje = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;

      socket.destroy();

      final data = jsonDecode(mensaje);

      return {
        'hdmi1': data['hdmi1'] ?? false,
        'hdmi2': data['hdmi2'] ?? false,
      };
    } catch (e) {
      debugPrint('Error al conectar con el servidor: $e');
      try {
        socket?.destroy();
      } catch (_) {}
      return {'hdmi1': false, 'hdmi2': false};
    }
  }
}
