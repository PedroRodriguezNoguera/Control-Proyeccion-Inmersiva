import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'home_screen.dart';
import 'config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializamos Hive y configuración
  await Hive.initFlutter();
  await ConfigService.init();

  // -----------------------------
  // 📦 BOXES EXISTENTES (VIDEOS/IMAGENES)
  // -----------------------------
  await Hive.openBox<String>('pantalla1'); // HDMI1 media
  await Hive.openBox<String>('pantalla2'); // HDMI2 media

  // -----------------------------
  // 📦 NUEVAS BOXES (MÁSCARAS)
  // -----------------------------
  await Hive.openBox<String>('masks_pantalla1');
  await Hive.openBox<String>('masks_pantalla2');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'App Tablet',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(),
    );
  }
}