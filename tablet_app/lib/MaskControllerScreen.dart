import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'server_connection.dart';
import 'package:video_player/video_player.dart';
import 'package:hive_flutter/hive_flutter.dart';

class MaskControllerScreen extends StatefulWidget {
  const MaskControllerScreen({super.key});

  @override
  State<MaskControllerScreen> createState() => _MaskControllerScreenState();
}

class _MaskControllerScreenState extends State<MaskControllerScreen> {
  List<MaskModel> masks = [];
  MaskModel? _copiedMask;
  String proSelected = "Pro1";

  // Id de la máscara seleccionada. Solo la seleccionada muestra controles de
  // redimensionado/borrado — el resto se ve limpia, para no saturar el lienzo.
  String? selectedMaskId;
  // Id de la forma transparente seleccionada dentro del donut activo.
  String? selectedCutoutId;
  bool _sidePanelExpanded = true;

  VideoPlayerController? videoController;
  bool isVideo = false;

  double backgroundWidth = 1;
  double backgroundHeight = 1;

  // Líneas guía de alineación al centro (espacio de pantalla), null = ocultas.
  double? _guideVerticalX;
  double? _guideHorizontalY;

  // Campos numéricos del panel de propiedades de la máscara seleccionada.
  final _xController = TextEditingController();
  final _yController = TextEditingController();
  final _wController = TextEditingController();
  final _hController = TextEditingController();
  final _xFocus = FocusNode();
  final _yFocus = FocusNode();
  final _wFocus = FocusNode();
  final _hFocus = FocusNode();

  // Campos numéricos de la forma transparente seleccionada (solo donut).
  final _ixController = TextEditingController();
  final _iyController = TextEditingController();
  final _iwController = TextEditingController();
  final _ihController = TextEditingController();
  final _ixFocus = FocusNode();
  final _iyFocus = FocusNode();
  final _iwFocus = FocusNode();
  final _ihFocus = FocusNode();

  String? _lastSyncedMaskId;
  String? _lastSyncedCutoutId;

  final Map<String, String> fallbackImages = {
    "Pro1": 'assets/fondo_proyector_pared.jpg',
    "Pro2": 'assets/FONDO PROYECTOR IMAN.jpg',
  };

  DateTime? _lastSend;
  Timer? _hiveSaveTimer;
  String _lastLoadedBox = "";

  // Margen alrededor de la imagen de fondo
  static const double _imageMargin = 35.0;

  // Proporción asumida de la pantalla/proyector real (16:9, la más habitual).
  // El lienzo de edición se bloquea a esta proporción para que el recorte
  // "cover" que se previsualiza aquí coincida con el de una pantalla real,
  // sea cual sea la orientación de la tablet. Ajustar si el hardware real
  // usa otra proporción.
  static const double _targetAspectRatio = 16 / 9;

  // Por debajo de este ancho de lienzo se usa el panel compacto (horizontal,
  // pensado para tablet en vertical) en vez del panel lateral fijo.
  static const double _portraitBreakpoint = 700.0;

  // Formas permitidas como recorte transparente dentro de un donut (no se
  // admite anidar un donut dentro de otro donut).
  static const List<MaskType> _cutoutShapes = [
    MaskType.circle,
    MaskType.square,
    MaskType.triangle,
  ];

  @override
  void initState() {
    super.initState();
    loadBackground();

    // Aplica el valor tecleado en cuanto el campo pierde el foco (no solo al
    // pulsar Enter), para que "tocar fuera" también confirme el cambio.
    _xFocus.addListener(() =>
        _commitPropertyField(_xFocus, _xController, (m, v) => m.x = v));
    _yFocus.addListener(() =>
        _commitPropertyField(_yFocus, _yController, (m, v) => m.y = v));
    _wFocus.addListener(() => _commitPropertyField(_wFocus, _wController,
        (m, v) => m.width = v.clamp(10.0, double.infinity)));
    _hFocus.addListener(() => _commitPropertyField(_hFocus, _hController,
        (m, v) => m.height = v.clamp(10.0, double.infinity)));

    _ixFocus.addListener(() =>
        _commitCutoutField(_ixFocus, _ixController, (c, v) => c.x = v));
    _iyFocus.addListener(() =>
        _commitCutoutField(_iyFocus, _iyController, (c, v) => c.y = v));
    _iwFocus.addListener(() => _commitCutoutField(_iwFocus, _iwController,
        (c, v) => c.width = v.clamp(10.0, double.infinity)));
    _ihFocus.addListener(() => _commitCutoutField(_ihFocus, _ihController,
        (c, v) => c.height = v.clamp(10.0, double.infinity)));
  }

  @override
  void dispose() {
    _hiveSaveTimer?.cancel();
    videoController?.dispose();
    _xController.dispose();
    _yController.dispose();
    _wController.dispose();
    _hController.dispose();
    _xFocus.dispose();
    _yFocus.dispose();
    _wFocus.dispose();
    _hFocus.dispose();
    _ixController.dispose();
    _iyController.dispose();
    _iwController.dispose();
    _ihController.dispose();
    _ixFocus.dispose();
    _iyFocus.dispose();
    _iwFocus.dispose();
    _ihFocus.dispose();
    super.dispose();
  }

  // Dimensiones (px) del contenido actualmente cargado — de la imagen fija o
  // del vídeo en reproducción. Es el sistema de coordenadas en el que se
  // guardan y transmiten todas las máscaras.
  Size get _sourceSize {
    if (isVideo) {
      if (videoController != null && videoController!.value.isInitialized) {
        final s = videoController!.value.size;
        if (s.width > 0 && s.height > 0) return s;
      }
      return const Size(1, 1);
    }
    return Size(backgroundWidth, backgroundHeight);
  }

  MaskModel? get selectedMask {
    if (selectedMaskId == null) return null;
    for (final m in masks) {
      if (m.id == selectedMaskId) return m;
    }
    return null;
  }

  MaskCutout? get selectedCutout {
    final m = selectedMask;
    if (m == null || selectedCutoutId == null) return null;
    for (final c in m.cutouts) {
      if (c.id == selectedCutoutId) return c;
    }
    return null;
  }

  void _selectMask(String? id) {
    setState(() {
      selectedMaskId = id;
      selectedCutoutId = null;
    });
  }

  void _selectCutout(String? id) {
    setState(() => selectedCutoutId = id);
  }

  // Clona una lista de recortes con ids nuevos (únicos incluso dentro del
  // mismo lote) y un desplazamiento opcional — usado por copiar/duplicar.
  List<MaskCutout> _cloneCutouts(List<MaskCutout> src,
      {double dx = 0, double dy = 0}) {
    final base = DateTime.now().microsecondsSinceEpoch;
    return [
      for (var i = 0; i < src.length; i++)
        MaskCutout(
          id: '${base}_$i',
          shape: src[i].shape,
          x: src[i].x + dx,
          y: src[i].y + dy,
          width: src[i].width,
          height: src[i].height,
        ),
    ];
  }

  void copyMask(MaskModel mask) {
    _copiedMask = MaskModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      x: mask.x + 20,
      y: mask.y + 20,
      width: mask.width,
      height: mask.height,
      type: mask.type,
      cutouts: _cloneCutouts(mask.cutouts, dx: 20, dy: 20),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Máscara copiada")),
    );
  }

  void pasteMask() {
    if (_copiedMask == null) return;

    final newMask = MaskModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      x: _copiedMask!.x,
      y: _copiedMask!.y,
      width: _copiedMask!.width,
      height: _copiedMask!.height,
      type: _copiedMask!.type,
      cutouts: _cloneCutouts(_copiedMask!.cutouts),
    );

    setState(() {
      masks.add(newMask);
      selectedMaskId = newMask.id;
      selectedCutoutId = null;
      sendMasks();
      saveMasksToHive();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Máscara pegada")),
    );
  }

  void duplicateMask(MaskModel mask) {
    final newMask = MaskModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      x: mask.x + 20,
      y: mask.y + 20,
      width: mask.width,
      height: mask.height,
      type: mask.type,
      cutouts: _cloneCutouts(mask.cutouts, dx: 20, dy: 20),
    );
    setState(() {
      masks.add(newMask);
      selectedMaskId = newMask.id;
      selectedCutoutId = null;
    });
    sendMasks();
    saveMasksToHive();
  }

  void send(String msg) {
    ServerConnection.instance.send(msg);
  }

  void throttledSendMasks() {
    final now = DateTime.now();
    if (_lastSend == null ||
        now.difference(_lastSend!).inMilliseconds > 30) {
      _lastSend = now;
      sendMasks();
    }
  }

  // Debounced: saves 100 ms after the last drag event so the final
  // position is always persisted without flooding disk at 60 fps.
  void debouncedSaveMasksToHive() {
    _hiveSaveTimer?.cancel();
    _hiveSaveTimer = Timer(const Duration(milliseconds: 100), saveMasksToHive);
  }

  // ---------------- HIVE MASKS ----------------

  String get maskBoxName =>
      proSelected == "Pro1" ? "masks_pantalla1" : "masks_pantalla2";

  void saveMasksToHive() {
    final box = Hive.box<String>(maskBoxName);

    final list = masks
        .map((m) => jsonEncode({
              "id": m.id,
              "x": m.x,
              "y": m.y,
              "width": m.width,
              "height": m.height,
              "type": m.type.index,
              "cutouts": m.cutouts
                  .map((c) => {
                        "id": c.id,
                        "shape": c.shape.index,
                        "x": c.x,
                        "y": c.y,
                        "width": c.width,
                        "height": c.height,
                      })
                  .toList(),
            }))
        .toList();

    box.put("data", jsonEncode(list));
  }

  List<MaskModel> _readMasksFromHive() {
    final box = Hive.box<String>(maskBoxName);
    final data = box.get("data");
    if (data == null) return [];
    final list = jsonDecode(data) as List;
    return list.map((e) {
      final map = jsonDecode(e);

      List<MaskCutout> cutouts = [];
      final rawCutouts = map["cutouts"] as List?;
      if (rawCutouts != null) {
        cutouts = rawCutouts
            .map((c) => MaskCutout(
                  id: c["id"] ?? DateTime.now().microsecondsSinceEpoch.toString(),
                  shape: MaskType.values[c["shape"]],
                  x: (c["x"] as num).toDouble(),
                  y: (c["y"] as num).toDouble(),
                  width: (c["width"] as num).toDouble(),
                  height: (c["height"] as num).toDouble(),
                ))
            .toList();
      } else if (map["innerX"] != null) {
        // Compatibilidad con el formato anterior (un único círculo interior
        // fijo, antes de que existieran varias formas independientes).
        cutouts = [
          MaskCutout(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            shape: MaskType.circle,
            x: (map["innerX"] as num).toDouble(),
            y: (map["innerY"] as num).toDouble(),
            width: (map["innerWidth"] as num).toDouble(),
            height: (map["innerHeight"] as num).toDouble(),
          ),
        ];
      }

      return MaskModel(
        id: map["id"],
        x: map["x"].toDouble(),
        y: map["y"].toDouble(),
        width: map["width"].toDouble(),
        height: map["height"].toDouble(),
        type: MaskType.values[map["type"]],
        cutouts: cutouts,
      );
    }).toList();
  }

  void loadMasksFromHive() {
    final boxName = maskBoxName;
    if (_lastLoadedBox == boxName) return;
    _lastLoadedBox = boxName;
    setState(() {
      masks = _readMasksFromHive();
    });
  }

  // ---------------- ORIGINAL ----------------

  void addMask([MaskType type = MaskType.circle]) {
    final newMask = MaskModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      x: 50,
      y: 50,
      width: 200,
      height: 200,
      type: type,
    );
    setState(() {
      masks.add(newMask);
      selectedMaskId = newMask.id;
      selectedCutoutId = null;
    });

    sendMasks();
    saveMasksToHive();
  }

  void _addCutout(MaskModel mask, MaskType shape) {
    final cutout = MaskCutout(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      shape: shape,
      x: mask.x + mask.width * 0.25,
      y: mask.y + mask.height * 0.25,
      width: mask.width * 0.5,
      height: mask.height * 0.5,
    );
    setState(() {
      mask.cutouts.add(cutout);
      selectedCutoutId = cutout.id;
    });
    sendMasks();
    saveMasksToHive();
  }

  void _deleteCutout(MaskModel mask, MaskCutout cutout) {
    setState(() {
      mask.cutouts.remove(cutout);
      if (selectedCutoutId == cutout.id) selectedCutoutId = null;
    });
    sendMasks();
    saveMasksToHive();
  }

  void sendMasks() {
    if (masks.isEmpty) {
      send("$proSelected CLEAR_MASKS");
      return;
    }
    // Cabecera <origW>,<origH>; con las dimensiones del contenido actual, para
    // que el servidor use exactamente el mismo sistema de referencia que la
    // tablet al posicionar las máscaras (incluye el caso de vídeo).
    final origW = _sourceSize.width.toInt();
    final origH = _sourceSize.height.toInt();
    // Las formas transparentes del donut (si tiene) van tras ":", separadas
    // entre sí por "~": <shape>,<x>,<y>,<w>,<h>~<shape>,<x>,<y>,<w>,<h>...
    final parts = masks.map((m) {
      final core =
          '${m.id},${m.x.toInt()},${m.y.toInt()},${m.width.toInt()},${m.height.toInt()},${m.type.index}';
      if (m.type == MaskType.donut && m.cutouts.isNotEmpty) {
        final cutoutsBlob = m.cutouts
            .map((c) =>
                '${c.shape.index},${c.x.toInt()},${c.y.toInt()},${c.width.toInt()},${c.height.toInt()}')
            .join('~');
        return '$core:$cutoutsBlob';
      }
      return core;
    }).join('|');
    send('$proSelected MASKS $origW,$origH;$parts');
  }

  Future<void> _confirmClearMasks() async {
    if (masks.isEmpty) return;
    final count = masks.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar todas las máscaras?'),
        content: Text(
            'Se eliminarán $count máscara${count == 1 ? '' : 's'} de $proSelected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed == true) _clearAllMasksWithUndo();
  }

  void _clearAllMasksWithUndo() {
    final snapshot = List<MaskModel>.from(masks);
    if (snapshot.isEmpty) return;

    send("$proSelected CLEAR_MASKS");
    setState(() {
      masks.clear();
      selectedMaskId = null;
      selectedCutoutId = null;
    });
    saveMasksToHive();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('${snapshot.length} máscara${snapshot.length == 1 ? '' : 's'} eliminadas'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            setState(() => masks = List<MaskModel>.from(snapshot));
            sendMasks();
            saveMasksToHive();
          },
        ),
      ),
    );
  }

  void _deleteMaskWithUndo(MaskModel mask) {
    final index = masks.indexOf(mask);
    if (index == -1) return;

    setState(() {
      masks.removeAt(index);
      if (selectedMaskId == mask.id) {
        selectedMaskId = null;
        selectedCutoutId = null;
      }
    });
    sendMasks();
    saveMasksToHive();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Máscara eliminada'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            setState(() {
              masks.insert(index.clamp(0, masks.length), mask);
              selectedMaskId = mask.id;
            });
            sendMasks();
            saveMasksToHive();
          },
        ),
      ),
    );
  }

  void loadBackground() async {
    videoController?.dispose();
    videoController = null;
    isVideo = false;

    final boxName = proSelected == "Pro1" ? 'pantalla1' : 'pantalla2';
    final box = Hive.box<String>(boxName);

    final ultimo = box.get('ultimo');

    if (ultimo != null) {
      if (ultimo.endsWith('.mp4')) {
        videoController = VideoPlayerController.file(File(ultimo))
          ..initialize().then((_) {
            videoController!.setLooping(true);
            videoController!.play();
            setState(() {});
            // Ahora que se conoce el tamaño real del vídeo, reenvía las
            // máscaras cacheadas para que el servidor tenga la referencia
            // correcta (antes esto nunca ocurría en modo vídeo).
            if (masks.isNotEmpty) sendMasks();
          });
        isVideo = true;
      } else if (ultimo.endsWith('.png') || ultimo.endsWith('.jpg')) {
        isVideo = false;
        final image = File(ultimo).existsSync()
            ? Image.file(File(ultimo))
            : Image.asset(ultimo);

        image.image.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener((ImageInfo info, bool _) {
            setState(() {
              backgroundWidth = info.image.width.toDouble();
              backgroundHeight = info.image.height.toDouble();
            });
            if (masks.isNotEmpty) sendMasks();
          }),
        );
      }
    } else {
      isVideo = false;
      final fallback = fallbackImages[proSelected]!;
      final image = Image.asset(fallback);
      image.image.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener((ImageInfo info, bool _) {
          setState(() {
            backgroundWidth = info.image.width.toDouble();
            backgroundHeight = info.image.height.toDouble();
          });
          if (masks.isNotEmpty) sendMasks();
        }),
      );
    }

    final maskBoxN = maskBoxName;
    _lastLoadedBox = maskBoxN;
    setState(() {
      masks = _readMasksFromHive();
      selectedMaskId = null;
      selectedCutoutId = null;
    });
  }

  // ---------------- CENTRO DE GUÍAS ----------------

  void _applyCenterSnap(
      MaskModel mask, double scale, double offsetLeft, double offsetTop, Size srcSize) {
    const thresholdScreenPx = 8.0;
    final thresholdSrc = thresholdScreenPx / scale;

    final centerX = mask.x + mask.width / 2;
    final centerY = mask.y + mask.height / 2;
    final srcCenterX = srcSize.width / 2;
    final srcCenterY = srcSize.height / 2;

    if ((centerX - srcCenterX).abs() < thresholdSrc) {
      mask.x = srcCenterX - mask.width / 2;
      _guideVerticalX = offsetLeft + srcCenterX * scale;
    } else {
      _guideVerticalX = null;
    }

    if ((centerY - srcCenterY).abs() < thresholdSrc) {
      mask.y = srcCenterY - mask.height / 2;
      _guideHorizontalY = offsetTop + srcCenterY * scale;
    } else {
      _guideHorizontalY = null;
    }
  }

  // ---------------- PANEL DE PROPIEDADES ----------------

  void _syncPropertyFields() {
    final m = selectedMask;
    if (m == null) {
      _lastSyncedMaskId = null;
    } else {
      final isNewSelection = m.id != _lastSyncedMaskId;
      _lastSyncedMaskId = m.id;
      if (isNewSelection || !_xFocus.hasFocus) {
        _xController.text = m.x.toStringAsFixed(0);
      }
      if (isNewSelection || !_yFocus.hasFocus) {
        _yController.text = m.y.toStringAsFixed(0);
      }
      if (isNewSelection || !_wFocus.hasFocus) {
        _wController.text = m.width.toStringAsFixed(0);
      }
      if (isNewSelection || !_hFocus.hasFocus) {
        _hController.text = m.height.toStringAsFixed(0);
      }
    }

    final c = selectedCutout;
    if (c == null) {
      _lastSyncedCutoutId = null;
      return;
    }
    final isNewCutout = c.id != _lastSyncedCutoutId;
    _lastSyncedCutoutId = c.id;
    if (isNewCutout || !_ixFocus.hasFocus) {
      _ixController.text = c.x.toStringAsFixed(0);
    }
    if (isNewCutout || !_iyFocus.hasFocus) {
      _iyController.text = c.y.toStringAsFixed(0);
    }
    if (isNewCutout || !_iwFocus.hasFocus) {
      _iwController.text = c.width.toStringAsFixed(0);
    }
    if (isNewCutout || !_ihFocus.hasFocus) {
      _ihController.text = c.height.toStringAsFixed(0);
    }
  }

  void _commitPropertyField(FocusNode focus, TextEditingController controller,
      void Function(MaskModel, double) apply) {
    if (focus.hasFocus) return;
    final mask = selectedMask;
    if (mask == null) return;
    final parsed = double.tryParse(controller.text);
    if (parsed == null) return;
    setState(() => apply(mask, parsed));
    sendMasks();
    saveMasksToHive();
  }

  void _commitCutoutField(FocusNode focus, TextEditingController controller,
      void Function(MaskCutout, double) apply) {
    if (focus.hasFocus) return;
    final cutout = selectedCutout;
    if (cutout == null) return;
    final parsed = double.tryParse(controller.text);
    if (parsed == null) return;
    setState(() => apply(cutout, parsed));
    sendMasks();
    saveMasksToHive();
  }

  // ---------------- ICONOS / ETIQUETAS ----------------

  IconData _iconForType(MaskType t) {
    switch (t) {
      case MaskType.circle:
        return Icons.circle_outlined;
      case MaskType.square:
        return Icons.crop_square;
      case MaskType.donut:
        return Icons.donut_large;
      case MaskType.triangle:
        return Icons.change_history;
    }
  }

  String _labelForType(MaskType t) {
    switch (t) {
      case MaskType.circle:
        return 'Círculo';
      case MaskType.square:
        return 'Cuadrado';
      case MaskType.donut:
        return 'Donut';
      case MaskType.triangle:
        return 'Triángulo';
    }
  }

  // ---------------- SELECTOR DE FORMA ----------------

  Future<MaskType?> _pickShape(String title, List<MaskType> shapes) {
    return showModalBottomSheet<MaskType>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: shapes.map((t) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(context, t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_iconForType(t),
                                    size: 28, color: Colors.black87),
                                const SizedBox(height: 8),
                                Text(_labelForType(t),
                                    style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showShapePicker() async {
    final type = await _pickShape('Añadir máscara', MaskType.values);
    if (type != null) addMask(type);
  }

  Future<void> _showCutoutShapePicker(MaskModel mask) async {
    final type =
        await _pickShape('Añadir forma transparente', _cutoutShapes);
    if (type != null) _addCutout(mask, type);
  }

  // ---------------- BUILD ----------------

  @override
  Widget build(BuildContext context) {
    final boxName = proSelected == "Pro1" ? 'pantalla1' : 'pantalla2';
    final box = Hive.box<String>(boxName);
    final ultimo = box.get('ultimo');
    final backgroundImage = ultimo ?? fallbackImages[proSelected]!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.grey.shade200,
        foregroundColor: Colors.black,
        title: const Text("Máscaras"),
        actions: [
          DropdownButton<String>(
            value: proSelected,
            dropdownColor: Colors.grey.shade200,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: "Pro1", child: Text("Pro1")),
              DropdownMenuItem(value: "Pro2", child: Text("Pro2")),
            ],
            onChanged: (value) {
              setState(() {
                proSelected = value!;
                masks = [];
                selectedMaskId = null;
                selectedCutoutId = null;
                _lastLoadedBox = "";
              });

              loadBackground();
              loadMasksFromHive();
              sendMasks();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Añadir máscara',
            onPressed: _showShapePicker,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Borrar todas',
            onPressed: _confirmClearMasks,
          ),
          IconButton(
            icon: Icon(_sidePanelExpanded ? Icons.menu_open : Icons.menu),
            tooltip: 'Panel de máscaras',
            onPressed: () =>
                setState(() => _sidePanelExpanded = !_sidePanelExpanded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Tablet en vertical (o ventana estrecha): panel compacto debajo
          // del lienzo en vez de columna lateral fija, para no dejarle al
          // lienzo un ancho demasiado reducido.
          final isPortrait = constraints.maxWidth < _portraitBreakpoint ||
              constraints.maxHeight > constraints.maxWidth;

          if (isPortrait) {
            return Column(
              children: [
                Expanded(child: _buildCanvas(backgroundImage)),
                if (_sidePanelExpanded) _buildBottomPanel(),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: _buildCanvas(backgroundImage)),
              if (_sidePanelExpanded) _buildSidePanel(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCanvas(String backgroundImage) {
    if (isVideo &&
        (videoController == null || !videoController!.value.isInitialized)) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(_imageMargin),
      child: LayoutBuilder(
        builder: (context, outer) {
          // El lienzo se bloquea a la proporción de la pantalla real
          // (16:9) y se centra en el espacio disponible, en vez de
          // estirarse a lo que sobre — así la previsualización "cover"
          // coincide con la de una pantalla real sea cual sea la
          // orientación/proporción de la tablet.
          double canvasW = outer.maxWidth;
          double canvasH = canvasW / _targetAspectRatio;
          if (canvasH > outer.maxHeight) {
            canvasH = outer.maxHeight;
            canvasW = canvasH * _targetAspectRatio;
          }

          final srcSize = _sourceSize;
          final scaleX = canvasW / srcSize.width;
          final scaleY = canvasH / srcSize.height;
          // Cover-fit (max, no min): coincide con el recorte "a pantalla
          // completa" que ya aplica el servidor (Math.max en Main.java) y
          // mpv (--panscan=1.0) — así lo que se ve aquí es lo que sale
          // realmente en el proyector, incluidos los bordes recortados.
          final scale = scaleX > scaleY ? scaleX : scaleY;

          final displayWidth = srcSize.width * scale;
          final displayHeight = srcSize.height * scale;
          final offsetLeft = (canvasW - displayWidth) / 2;
          final offsetTop = (canvasH - displayHeight) / 2;

          final selMask = selectedMask;

          return Center(
            child: Container(
              width: canvasW,
              height: canvasH,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                // Recorta exactamente al borde de pantalla, igual que el servidor.
                borderRadius: BorderRadius.circular(5),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Capa de fondo: tocar aquí deselecciona la máscara activa.
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selectMask(null),
                      ),
                    ),

                    // Imagen o vídeo de fondo, recortados igual que en el servidor.
                    Positioned(
                      left: offsetLeft,
                      top: offsetTop,
                      child: SizedBox(
                        width: displayWidth,
                        height: displayHeight,
                        child: isVideo
                            ? VideoPlayer(videoController!)
                            : Container(
                                decoration: BoxDecoration(
                                  image: DecorationImage(
                                    image: File(backgroundImage).existsSync()
                                        ? FileImage(File(backgroundImage))
                                        : AssetImage(backgroundImage)
                                            as ImageProvider,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                              ),
                      ),
                    ),

                    for (var mask in masks)
                      _buildMaskWidget(
                          mask, scale, offsetLeft, offsetTop, srcSize),

                    // Handles de las formas transparentes del donut
                    // seleccionado — por encima de todo para poder
                    // agarrarlas aunque queden dentro del rectángulo negro.
                    if (selMask != null && selMask.type == MaskType.donut)
                      for (var cutout in selMask.cutouts)
                        _buildCutoutWidget(
                            selMask, cutout, scale, offsetLeft, offsetTop),

                    if (_guideVerticalX != null)
                      Positioned(
                        left: _guideVerticalX! - 0.5,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Container(
                            width: 1,
                            color: Colors.blueAccent.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    if (_guideHorizontalY != null)
                      Positioned(
                        top: _guideHorizontalY! - 0.5,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Container(
                            height: 1,
                            color: Colors.blueAccent.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMaskWidget(MaskModel mask, double scale, double offsetLeft,
      double offsetTop, Size srcSize) {
    final isSelected = mask.id == selectedMaskId;

    return Positioned(
      left: offsetLeft + mask.x * scale,
      top: offsetTop + mask.y * scale,
      child: GestureDetector(
        // Opaco: absorbe el toque dentro de sus límites para que no llegue a
        // la capa de fondo (evita que seleccionar una máscara la deseleccione
        // en el mismo gesto) y, si hay máscaras solapadas, gana la de encima.
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectMask(mask.id),

        onLongPressStart: (details) async {
          final selected = await showMenu(
            context: context,
            position: RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              details.globalPosition.dx,
              details.globalPosition.dy,
            ),
            items: const [
              PopupMenuItem(value: "copy", child: Text("Copiar")),
              PopupMenuItem(value: "paste", child: Text("Pegar")),
              PopupMenuItem(value: "delete", child: Text("Eliminar")),
            ],
          );

          if (selected == "copy") copyMask(mask);
          if (selected == "paste") pasteMask();
          if (selected == "delete") _deleteMaskWithUndo(mask);
        },

        onSecondaryTapDown: (details) async {
          final selected = await showMenu(
            context: context,
            position: RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              details.globalPosition.dx,
              details.globalPosition.dy,
            ),
            items: const [
              PopupMenuItem(value: "copy", child: Text("Copiar")),
              PopupMenuItem(value: "paste", child: Text("Pegar")),
              PopupMenuItem(value: "delete", child: Text("Eliminar")),
            ],
          );

          if (selected == "copy") copyMask(mask);
          if (selected == "paste") pasteMask();
          if (selected == "delete") _deleteMaskWithUndo(mask);
        },

        onPanStart: (_) => _selectMask(mask.id),

        onPanUpdate: (details) {
          setState(() {
            mask.x += details.delta.dx / scale;
            mask.y += details.delta.dy / scale;
            _applyCenterSnap(mask, scale, offsetLeft, offsetTop, srcSize);

            throttledSendMasks();
            debouncedSaveMasksToHive();
          });
        },

        onPanEnd: (_) => setState(() {
          _guideVerticalX = null;
          _guideHorizontalY = null;
        }),

        child: SizedBox(
          width: mask.width * scale,
          height: mask.height * scale,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(mask.width * scale, mask.height * scale),
                painter: MaskPainter(
                  mask.type,
                  cutouts: mask.type == MaskType.donut
                      ? mask.cutouts
                          .map((c) => LocalCutout(
                                c.shape,
                                Rect.fromLTWH(
                                  (c.x - mask.x) * scale,
                                  (c.y - mask.y) * scale,
                                  c.width * scale,
                                  c.height * scale,
                                ),
                              ))
                          .toList()
                      : const [],
                ),
              ),

              if (isSelected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blueAccent, width: 2),
                      ),
                    ),
                  ),
                ),

              if (isSelected) ..._buildHandles(mask, scale),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildHandles(MaskModel mask, double scale) {
    return [
      // Esquina inferior derecha: redimensiona proporcionalmente (ancho=alto).
      Positioned(
        right: 0,
        bottom: 0,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              double delta = details.delta.dx / scale;
              mask.width = (mask.width + delta).clamp(10.0, double.infinity);
              mask.height = (mask.height + delta).clamp(10.0, double.infinity);

              throttledSendMasks();
              debouncedSaveMasksToHive();
            });
          },
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blueAccent, width: 2),
            ),
            child: const Icon(Icons.open_in_full,
                size: 12, color: Colors.blueAccent),
          ),
        ),
      ),

      // Borde derecho: ancho.
      Positioned(
        right: -10,
        top: (mask.height * scale) / 2 - 10,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              mask.width =
                  (mask.width + details.delta.dx / scale).clamp(10.0, double.infinity);

              throttledSendMasks();
              debouncedSaveMasksToHive();
            });
          },
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.orange, width: 2),
            ),
            child: const Icon(Icons.swap_horiz, size: 11, color: Colors.orange),
          ),
        ),
      ),

      // Borde inferior: alto.
      Positioned(
        left: (mask.width * scale) / 2 - 10,
        bottom: -10,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              mask.height =
                  (mask.height + details.delta.dy / scale).clamp(10.0, double.infinity);

              throttledSendMasks();
              debouncedSaveMasksToHive();
            });
          },
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green, width: 2),
            ),
            child: const Icon(Icons.swap_vert, size: 11, color: Colors.green),
          ),
        ),
      ),

      // Eliminar.
      Positioned(
        top: -12,
        right: -12,
        child: GestureDetector(
          onTap: () => _deleteMaskWithUndo(mask),
          child: Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 16),
          ),
        ),
      ),
    ];
  }

  // Handle de una forma transparente del donut: se puede mover y
  // redimensionar por separado del rectángulo negro exterior y del resto de
  // formas transparentes. El interior es realmente invisible en el
  // resultado final — el contorno de aquí es solo una guía visual para
  // poder verlo y agarrarlo mientras se edita.
  Widget _buildCutoutWidget(MaskModel mask, MaskCutout cutout, double scale,
      double offsetLeft, double offsetTop) {
    final isSelected = cutout.id == selectedCutoutId;

    return Positioned(
      left: offsetLeft + cutout.x * scale,
      top: offsetTop + cutout.y * scale,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectCutout(cutout.id),
        onPanStart: (_) => _selectCutout(cutout.id),
        onPanUpdate: (details) {
          setState(() {
            cutout.x += details.delta.dx / scale;
            cutout.y += details.delta.dy / scale;

            throttledSendMasks();
            debouncedSaveMasksToHive();
          });
        },
        child: SizedBox(
          width: cutout.width * scale,
          height: cutout.height * scale,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CutoutOutlinePainter(cutout.shape, isSelected),
                  ),
                ),
              ),

              if (isSelected) ...[
                // Redimensiona la forma (proporcional, ancho=alto).
                Positioned(
                  right: -9,
                  bottom: -9,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        final delta = details.delta.dx / scale;
                        cutout.width =
                            (cutout.width + delta).clamp(10.0, double.infinity);
                        cutout.height =
                            (cutout.height + delta).clamp(10.0, double.infinity);

                        throttledSendMasks();
                        debouncedSaveMasksToHive();
                      });
                    },
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.purpleAccent, width: 2),
                      ),
                      child: const Icon(Icons.open_in_full,
                          size: 10, color: Colors.purpleAccent),
                    ),
                  ),
                ),

                // Elimina esta forma transparente.
                Positioned(
                  top: -10,
                  left: -10,
                  child: GestureDetector(
                    onTap: () => _deleteCutout(mask, cutout),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.purpleAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel() {
    _syncPropertyFields();
    final selected = selectedMask;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'Máscaras (${masks.length})',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ),
          ),
          Expanded(
            child: masks.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: masks.length,
                    itemBuilder: (context, index) {
                      final m = masks[index];
                      final isSelected = m.id == selectedMaskId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Material(
                          color: isSelected
                              ? Colors.blueAccent.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _selectMask(m.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.blueAccent
                                      : Colors.grey.shade300,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(_iconForType(m.type),
                                      size: 20, color: Colors.black87),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${_labelForType(m.type)} ${index + 1}',
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
                                    tooltip: 'Duplicar',
                                    onPressed: () => duplicateMask(m),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    splashRadius: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18),
                                    tooltip: 'Eliminar',
                                    onPressed: () => _deleteMaskWithUndo(m),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    splashRadius: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (selected != null) _buildPropertiesCard(),
        ],
      ),
    );
  }

  Widget _buildEmptyState({bool compact = false}) {
    if (compact) {
      return Center(
        child: Text(
          'No hay máscaras · toca + para añadir una',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.crop_free, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No hay máscaras',
              style: TextStyle(
                  color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Toca + para añadir una',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- PANEL COMPACTO (TABLET VERTICAL) ----------------

  Widget _buildBottomPanel() {
    _syncPropertyFields();
    final selected = selectedMask;

    final panelMaxHeight = selected == null
        ? 130.0
        : (selected.type == MaskType.donut ? 420.0 : 260.0);
    return Container(
      constraints: BoxConstraints(maxHeight: panelMaxHeight),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  'Máscaras (${masks.length})',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 92,
            child: masks.isEmpty
                ? _buildEmptyState(compact: true)
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: masks.length,
                    itemBuilder: (context, index) =>
                        _buildMaskChip(masks[index], index),
                  ),
          ),
          if (selected != null)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: _buildPropertiesFields(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMaskChip(MaskModel m, int index) {
    final isSelected = m.id == selectedMaskId;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: Material(
        color:
            isSelected ? Colors.blueAccent.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectMask(m.id),
          child: Container(
            width: 108,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.blueAccent : Colors.grey.shade300,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconForType(m.type), size: 20, color: Colors.black87),
                const SizedBox(height: 2),
                Text(
                  '${_labelForType(m.type)} ${index + 1}',
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy, size: 14),
                      tooltip: 'Duplicar',
                      onPressed: () => duplicateMask(m),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 12,
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 14),
                      tooltip: 'Eliminar',
                      onPressed: () => _deleteMaskWithUndo(m),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 12,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPropertiesCard() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Propiedades',
            style:
                TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 10),
          _buildPropertiesFields(),
        ],
      ),
    );
  }

  Widget _buildPropertiesFields() {
    final mask = selectedMask;
    final isDonut = mask?.type == MaskType.donut;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _propertyField('X', _xController, _xFocus)),
            const SizedBox(width: 8),
            Expanded(child: _propertyField('Y', _yController, _yFocus)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _propertyField('W', _wController, _wFocus)),
            const SizedBox(width: 8),
            Expanded(child: _propertyField('H', _hController, _hFocus)),
          ],
        ),
        if (isDonut) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Formas transparentes',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple.shade300),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showCutoutShapePicker(mask!),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.add_circle_outline,
                      size: 18, color: Colors.purpleAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (mask!.cutouts.isEmpty)
            Text(
              'Ninguna · toca + para añadir',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: mask.cutouts.map((c) {
                final isSelected = c.id == selectedCutoutId;
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _selectCutout(c.id),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.purpleAccent.withValues(alpha: 0.12)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? Colors.purpleAccent
                            : Colors.grey.shade300,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_iconForType(c.shape),
                            size: 14, color: Colors.black87),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => _deleteCutout(mask, c),
                          child: const Icon(Icons.close,
                              size: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          if (selectedCutout != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _propertyField('X', _ixController, _ixFocus)),
                const SizedBox(width: 8),
                Expanded(child: _propertyField('Y', _iyController, _iyFocus)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _propertyField('W', _iwController, _iwFocus)),
                const SizedBox(width: 8),
                Expanded(child: _propertyField('H', _ihController, _ihFocus)),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _propertyField(
      String label, TextEditingController controller, FocusNode focus) {
    return TextField(
      controller: controller,
      focusNode: focus,
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onSubmitted: (_) => focus.unfocus(),
    );
  }
}

// ---------------- MODELOS Y PAINTERS ----------------

// Forma transparente independiente recortada sobre un donut — propia
// posición/tamaño/forma (círculo, cuadrado o triángulo), en el mismo
// espacio de coordenadas que la máscara que la contiene.
class MaskCutout {
  String id;
  MaskType shape;
  double x;
  double y;
  double width;
  double height;

  MaskCutout({
    required this.id,
    required this.shape,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class MaskModel {
  String id;
  double x;
  double y;
  double width;
  double height;
  MaskType type;

  // Solo relevante para MaskType.donut: lista de formas transparentes
  // recortadas sobre el rectángulo negro, cada una independiente.
  List<MaskCutout> cutouts;

  MaskModel({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.type,
    List<MaskCutout>? cutouts,
  }) : cutouts = cutouts ?? [];
}

enum MaskType { circle, square, donut, triangle }

// Recorte transparente ya convertido a coordenadas locales (relativas al
// propio rectángulo del donut, escaladas a pantalla) — usado por MaskPainter.
class LocalCutout {
  final MaskType shape;
  final Rect rect;
  const LocalCutout(this.shape, this.rect);
}

Path _shapePath(MaskType type, Rect rect) {
  switch (type) {
    case MaskType.circle:
      return Path()..addOval(rect);
    case MaskType.square:
      return Path()..addRect(rect);
    case MaskType.triangle:
      return Path()
        ..moveTo(rect.left + rect.width / 2, rect.top)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close();
    case MaskType.donut:
      return Path()..addRect(rect);
  }
}

class MaskPainter extends CustomPainter {
  final MaskType type;
  // Formas transparentes recortadas del donut — vacío para el resto de formas.
  final List<LocalCutout> cutouts;

  MaskPainter(this.type, {this.cutouts = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    if (type == MaskType.donut) {
      // Rectángulo negro opaco con cada forma transparente recortada —
      // igual que el servidor (Area.subtract en Main.java).
      var path = Path()..addRect(fullRect);
      for (final cutout in cutouts) {
        path = Path.combine(
          PathOperation.difference,
          path,
          _shapePath(cutout.shape, cutout.rect),
        );
      }
      canvas.drawPath(path, paint);
      return;
    }

    canvas.drawPath(_shapePath(type, fullRect), paint);
  }

  @override
  bool shouldRepaint(MaskPainter oldDelegate) => true;
}

// Contorno visual (sin relleno) de una forma transparente del donut, para
// poder verla y agarrarla mientras se edita — el interior real es invisible.
class _CutoutOutlinePainter extends CustomPainter {
  final MaskType shape;
  final bool selected;

  _CutoutOutlinePainter(this.shape, this.selected);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = selected
          ? Colors.purpleAccent
          : Colors.purpleAccent.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    canvas.drawPath(_shapePath(shape, rect), paint);
  }

  @override
  bool shouldRepaint(covariant _CutoutOutlinePainter oldDelegate) =>
      shape != oldDelegate.shape || selected != oldDelegate.selected;
}
