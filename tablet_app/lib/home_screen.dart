import 'dart:async';
import 'package:flutter/material.dart';
import 'hdmi_service.dart';
import 'pared_menu_screen.dart';
import 'iman_menu_screen.dart';
import 'admin_screen.dart';
import 'config_service.dart';
import 'server_connection.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool hdmi1Conectado = false;
  bool hdmi2Conectado = false;
  bool cargando = true;
  bool reiniciando = false;
  bool _errorConexion = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _consultarHdmi();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _consultarHdmi(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consultarHdmi();
      _timer ??= Timer.periodic(
        const Duration(seconds: 10),
        (_) => _consultarHdmi(),
      );
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _consultarHdmi() async {
    try {
      final service = HdmiService(servidorIp: ConfigService.serverIp);

      final estado = await service.obtenerEstadoHdmi().timeout(
        const Duration(seconds: 10),
        onTimeout: () => {'hdmi1': false, 'hdmi2': false},
      );

      if (!mounted) return;
      setState(() {
        hdmi1Conectado = estado['hdmi1'] ?? false;
        hdmi2Conectado = estado['hdmi2'] ?? false;
        cargando = false;
        _errorConexion = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        hdmi1Conectado = false;
        hdmi2Conectado = false;
        cargando = false;
        _errorConexion = true;
      });
    }
  }

  Future<void> _reiniciarServidor() async {
    setState(() => reiniciando = true);
    try {
      await ServerConnection.instance.send('restart');
      ServerConnection.instance.reset();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Servidor reiniciado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al reiniciar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => reiniciando = false);
    }
  }

  void _confirmarReinicio() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Reiniciar servidor',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        content: const Text(
          '¿Seguro que quieres reiniciar el servidor?',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w300),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _reiniciarServidor();
            },
            child: const Text(
              'Reiniciar',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  void _pedirContrasena() {
    final TextEditingController passController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Acceso',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 20,
          ),
        ),
        content: TextField(
          controller: passController,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Contraseña',
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              if (ConfigService.checkAdminPassword(passController.text)) {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminScreen(),
                  ),
                ).then((_) {
                  // Al volver de Ajustes, refresca por si cambió el orden
                  // de los botones (u otra preferencia) — si no, se quedaba
                  // con el valor antiguo hasta el siguiente sondeo de HDMI.
                  if (mounted) setState(() {});
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contraseña incorrecta'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(
              'Entrar',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/IMG_MENU_PRINCIPAL_19_19.jpg',
            fit: BoxFit.cover,
          ),

          Positioned(
            top: 20,
            right: 20,
            child: Row(
              children: [
                reiniciando
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.black,
                        ),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.restart_alt,
                          size: 32,
                          color: Colors.black,
                        ),
                        onPressed: _confirmarReinicio,
                      ),
                IconButton(
                  icon: const Icon(
                    Icons.settings,
                    size: 32,
                    color: Colors.black,
                  ),
                  onPressed: _pedirContrasena,
                ),
              ],
            ),
          ),

          if (_errorConexion && !cargando)
            Positioned(
              bottom: 8,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade700.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Sin conexión con el servidor',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: screenHeight * 0.09),
              child: _buildButtonArea(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtonArea(BuildContext context) {
    final _HomeButtonItem? paredItem = (hdmi1Conectado || cargando)
        ? (
            imagen: 'assets/proyeccion_pared.jpg',
            texto: 'PARED',
            activo: hdmi1Conectado,
            onTap: () {
              if (!hdmi1Conectado) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ParedMenuScreen()),
              );
            },
          )
        : null;

    final _HomeButtonItem? imanItem = (hdmi2Conectado || cargando)
        ? (
            imagen: 'assets/proyeccion_iman.jpg',
            texto: 'IMÁN',
            activo: hdmi2Conectado,
            onTap: () {
              if (!hdmi2Conectado) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImanMenuScreen()),
              );
            },
          )
        : null;

    if (paredItem == null && imanItem == null) return const SizedBox.shrink();

    // Orden de los dos huecos según la preferencia guardada en Ajustes — cada
    // botón siempre ocupa el mismo hueco (izquierda/derecha) tanto si el otro
    // proyector está conectado como si no, en vez de centrarse solo.
    final slots = ConfigService.swapHomeButtons
        ? [imanItem, paredItem]
        : [paredItem, imanItem];

    Widget slotWidget(_HomeButtonItem? item) {
      if (item == null) return const SizedBox.shrink();
      return Opacity(
        opacity: item.activo ? 1.0 : 0.5,
        child: _buildBoton(
          imagen: item.imagen,
          texto: item.texto,
          onTap: item.onTap,
        ),
      );
    }

    return Row(
      children: [
        Expanded(child: slotWidget(slots[0])),
        const SizedBox(width: 20),
        Expanded(child: slotWidget(slots[1])),
      ],
    );
  }

  Widget _buildBoton({
    required String imagen,
    required String texto,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 3 / 2,
                child: Image.asset(
                  imagen,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          texto,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

typedef _HomeButtonItem = ({
  String imagen,
  String texto,
  VoidCallback onTap,
  bool activo,
});