import 'package:flutter/material.dart';
import 'iman_videos_screen.dart';
import 'home_screen.dart';
import 'iman_fotos_screen.dart';

class ImanMenuScreen extends StatelessWidget {
  const ImanMenuScreen({super.key});

  // Bordes de los botones
  static const double borderRadius = 30;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo que se ajusta a toda la pantalla
          Image.asset(
            'assets/FONDO PROYECTOR IMAN.jpg',
            fit: BoxFit.cover,
          ),

          // Botones y textos
          Column(
            children: [
              // Espacio superior para mover los botones hacia abajo
              Spacer(flex: 3), 

              // Botón "IMAGEN"
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ImanFotosScreenHDMI2(),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(borderRadius),
                          child: Image.asset(
                            'assets/proyeccion_iman.jpg',
                            fit: BoxFit.cover,
                            width: screenWidth * 0.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'IMAGEN',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ],
                ),
              ),

              // Espacio entre botones
              Spacer(flex: 1),

              // Botón "VIDEO"
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ImanVideosScreenHDMI2(),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(borderRadius),
                          child: Image.asset(
                            'assets/BOTON_VIDEO_IMAN.gif',
                            fit: BoxFit.cover,
                            width: screenWidth * 0.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'VIDEO',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ],
                ),
              ),

              // Espacio inferior
              Spacer(flex: 2),
            ],
          ),

          // Botón invisible arriba derecha para volver a HomeScreen
          Positioned(
            top: 0,
            right: 0,
            child: SizedBox(
              width: 180,
              height: 100,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.transparent,
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HomeScreen(),
                    ),
                  );
                },
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
