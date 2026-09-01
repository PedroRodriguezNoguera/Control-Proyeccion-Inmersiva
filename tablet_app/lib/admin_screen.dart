import 'package:flutter/material.dart';
import 'config_service.dart';
import 'server_connection.dart';
import 'MaskControllerScreen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final TextEditingController _ipController =
      TextEditingController(text: ConfigService.serverIp);

  bool _swapButtons = ConfigService.swapHomeButtons;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  void _setSwapButtons(bool value) {
    setState(() => _swapButtons = value);
    ConfigService.setSwapHomeButtons(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Configuración',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  labelText: 'IP del servidor',
                ),
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {
                ConfigService.setServerIp(_ipController.text);
                ServerConnection.instance.reset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('IP actualizada correctamente'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Guardar IP',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 28),

            const Text(
              'Orden de los botones de inicio',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Elige qué proyector aparece a la izquierda en la pantalla de inicio.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _OrderOption(
                    label: 'PARED · IMÁN',
                    selected: !_swapButtons,
                    onTap: () => _setSwapButtons(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OrderOption(
                    label: 'IMÁN · PARED',
                    selected: _swapButtons,
                    onTap: () => _setSwapButtons(true),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MaskControllerScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Configuración de Proyección',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OrderOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent.withValues(alpha: 0.08) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.blueAccent : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.blueAccent : Colors.black87,
          ),
        ),
      ),
    );
  }
}
