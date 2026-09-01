# Control de Proyección Inmersiva

Sistema de control remoto para salas de proyección inmersiva: una tablet decide qué imagen o vídeo se proyecta sobre cada una de hasta dos superficies independientes (por ejemplo, la pared de una sala y una segunda superficie de geometría particular), y un servidor de escritorio en Windows reproduce ese contenido en tiempo real sobre los proyectores correspondientes, con máscaras de recorte editables para que la proyección encaje con precisión incluso en superficies curvas o con huecos.

**Proyecto completo y funcional, no una maqueta.** Ya se ha desplegado en entornos reales y sigue en uso activo hoy en día.

## Posibles escenarios de uso

El sistema es agnóstico al contenido y al espacio: cualquier situación en la que se necesite cambiar sobre la marcha lo que se proyecta en una sala, sin tocar el ordenador que gestiona los proyectores. Algunos ejemplos:

- **Espacios de bienestar y experiencia del usuario** — proyecciones relajantes o inmersivas en salas de espera, tratamientos o experiencias sensoriales.
- **Museos y exposiciones** — cambiar el contenido proyectado en una sala según la visita o la hora, sin personal técnico especializado.
- **Espacios comerciales y showrooms** — escaparates o salas de marca con contenido audiovisual controlado en directo.
- **Eventos y escape rooms** — sincronizar vídeo/imagen con la narrativa de una experiencia en tiempo real.

## Cómo funciona por dentro

- **App de control (Flutter — Windows/Android/iOS)**: pantallas de selección de imagen/vídeo para cada superficie de proyección, un editor visual de máscaras de recorte y una pantalla de administración con PIN.
- **Editor de máscaras en vivo**: sobre una vista previa a la proporción real del proyector (16:9, bloqueada para que el recorte "cover" coincida exactamente con lo que se ve en la sala), se pueden añadir, arrastrar, redimensionar, duplicar y deshacer formas (círculo, cuadrado, triángulo, o un "donut" con varias formas transparentes independientes recortadas dentro). Cada cambio se envía al servidor en tiempo real (con throttling para no saturar la red) y se persiste localmente con debounce.
- **Protocolo propio sobre TCP**: la tablet y el servidor hablan mediante mensajes de texto simples (`Pro1 MASKS ...`, `Pro2 status`...) sobre un socket TCP con reconexión automática — sin dependencias externas ni brokers de mensajería.
- **Servidor multipantalla (Java)**: un `ServerSocket` multihilo atiende conexiones de la tablet y, por cada proyector, controla una instancia de `mpv` vía pipes IPC (reproducción de vídeo en bucle a pantalla completa) y superpone una ventana transparente que dibuja las máscaras activas — recortando formas con operaciones de `Area` de Java 2D — para que las máscaras se vean como negro sólido flotando sobre el vídeo/imagen en directo.
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

Las imágenes de fondo e iconos incluidas son *placeholders* genéricos pensados para este repositorio. La app funciona igual con contenido propio — solo cambia el material visual de ejemplo.
