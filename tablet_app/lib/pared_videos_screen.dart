import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'media_constants.dart';
import 'server_connection.dart';

class ParedVideosScreenHDMI1 extends StatefulWidget {
  const ParedVideosScreenHDMI1({super.key});

  @override
  State<ParedVideosScreenHDMI1> createState() => _ParedVideosScreenHDMI1State();
}

class _ParedVideosScreenHDMI1State extends State<ParedVideosScreenHDMI1> {
  late final Box<String> _box;
  String? _ultimo;

  static const double _borderRadius = 16;

  @override
  void initState() {
    super.initState();
    _box = Hive.box('pantalla1');
    _ultimo = _box.get('ultimo');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final item in kVideosItems) {
        precacheImage(AssetImage(item['image']!), context);
      }
    });
  }

  void _onTap(Map<String, String> item) {
    final asset = item['image']!;
    ServerConnection.instance.send('Pro1 ${item['keyPro1']!}');
    _box.put('ultimo', asset);
    setState(() => _ultimo = asset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/FONDO PARED VIDEOS.jpg', fit: BoxFit.cover),

          Positioned(
            top: 0,
            right: 0,
            child: SizedBox(
              width: 120,
              height: 60,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const SizedBox.shrink(),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(40, 180, 40, 80),
            child: GridView.builder(
              itemCount: kVideosItems.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 30,
                mainAxisSpacing: 30,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final item = kVideosItems[index];
                final asset = item['image']!;
                final selected = _ultimo == asset;

                return GestureDetector(
                  onTap: () => _onTap(item),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_borderRadius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(asset, fit: BoxFit.cover),
                        if (selected)
                          Container(color: Colors.black.withOpacity(0.3)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
