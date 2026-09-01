# Immersive Scan Projection Controller

Sistema de control remoto para una sala de proyección inmersiva: una tablet Android/iOS decide qué imagen o vídeo se proyecta — en la pared de la sala o dentro del túnel de un escáner (resonancia magnética, TAC...) — y un servidor de escritorio en Windows reproduce ese contenido en tiempo real sobre dos proyectores independientes, con máscaras de recorte editables para que la proyección encaje con precisión en superficies curvas o con huecos.

**Proyecto completo y funcional, no una maqueta.** Diseñado, desarrollado y desplegado en una instalación real, donde sigue en producción a día de hoy.

## Qué resuelve

Los escáneres médicos (resonancias, TAC) son una experiencia estresante: el paciente pasa varios minutos inmóvil dentro de un túnel estrecho y ruidoso. Proyectar un paisaje relajante en las paredes de la sala o directamente en el interior del túnel ayuda a reducir esa ansiedad — pero alguien tiene que poder cambiar ese contenido al vuelo, sin tocar el ordenador que gestiona los proyectores, y sin que el ajuste de la proyección (posición, recorte, forma) requiera reprogramar nada cada vez que cambia el mobiliario o el escáner.

Este sistema separa esas dos responsabilidades: una tablet sencilla para el personal de la sala, y un servidor dedicado que hace el trabajo pesado de vídeo/proyección, hablando entre sí por red local.

## Cómo funciona por dentro

- **App de control (Flutter — Windows/Android/iOS)**: pantallas de selección de imagen/vídeo para cada superficie de proyección ("pared" y "túnel/imán"), un editor visual de máscaras de recorte y una pantalla de administración con PIN.
- **Editor de máscaras en vivo**: sobre una vista previa a la proporción real del proyector (16:9, bloqueada para que el recorte "cover" coincida exactamente con lo que se ve en la sala), se pueden añadir, arrastrar, redimensionar, duplicar y deshacer formas (círculo, cuadrado, triángulo, o un "donut" con varias formas transparentes independientes recortadas dentro). Cada cambio se envía al servidor en tiempo real (con throttling para no saturar la red) y se persiste localmente con debounce.
- **Protocolo propio sobre TCP**: la tablet y el servidor hablan mediante mensajes de texto simples (`Pro1 MASKS ...`, `Pro2 status`...) sobre un socket TCP con reconexión automática — sin dependencias externas ni brokers de mensajería.
- **Servidor multipantalla (Java)**: un `ServerSocket` multihilo atiende conexiones de la tablet y, por cada uno de los dos proyectores, controla una instancia de `mpv` vía pipes IPC (reproducción de vídeo en bucle a pantalla completa) y superpone una ventana transparente que dibuja las máscaras activas — recortando formas con operaciones de `Area` de Java 2D — para que las máscaras se vean como negro sólido flotando sobre el vídeo/imagen en directo.
- **Caché LRU de imágenes** en el servidor para no releer del disco constantemente al cambiar de contenido.
- **Arranque automático**: un script de sistema compila el servidor, detecta cuántas pantallas hay conectadas y lanza tanto `mpv` como el servidor Java en el orden correcto tras el arranque de la máquina.

## Stack técnico

- **Flutter** (Dart) — app de control multiplataforma (validado en Windows y Android)
- **Hive** — persistencia local ligera (últimas máscaras, contenido seleccionado, configuración, PIN hasheado con SHA-256)
- **Sockets TCP** (`dart:io` / `java.net`) — protocolo de comandos propio entre tablet y servidor
- **Java 8** + **vlcj / mpv (IPC)** — reproducción de vídeo en los proyectores
- **Java 2D** (`Area`, `BufferedImage`) — composición de máscaras con recortes arbitrarios en tiempo real
- **Maven** — build del servidor

## Estructura del repositorio

```
tablet_app/    App Flutter que corre en la tablet de control
server_app/    Servidor Java que controla mpv y los proyectores
```

## Puesta en marcha

**App de control**
```bash
cd tablet_app
flutter pub get
flutter run
```
La IP y puerto del servidor se configuran desde la propia app (pantalla de Configuración, protegida por PIN).

**Servidor**
```bash
cd server_app
mvn compile
java -cp "target/classes;src/main/lib/*" uk.co.caprica.Main
```
Requiere `mpv` instalado y accesible, y las rutas de contenido configuradas en `config.properties`. `START_ALL.bat` automatiza compilación + arranque de `mpv` (una o dos pantallas, detectadas automáticamente) + servidor, pensado para lanzarse al arrancar la máquina dedicada.

## Nota sobre las imágenes de este repositorio

Las imágenes de fondo, iconos y capturas reales de la instalación se han sustituido por *placeholders* genéricos para no publicar contenido específico del cliente/instalación real. La app funciona igual con ellas — solo cambia el contenido visual de ejemplo.
