package uk.co.caprica;

import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.awt.Color;
import java.awt.Graphics;
import java.awt.Graphics2D;
import java.awt.DisplayMode;
import java.awt.GraphicsConfiguration;
import java.awt.GraphicsDevice;
import java.awt.GraphicsEnvironment;
import java.awt.Polygon;
import java.awt.RenderingHints;
import java.awt.Shape;
import java.awt.Transparency;
import java.awt.geom.Area;
import java.awt.geom.Ellipse2D;
import java.awt.geom.Rectangle2D;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import javax.swing.*;

public class Main {

    private static final GraphicsDevice[] screens =
        GraphicsEnvironment.getLocalGraphicsEnvironment().getScreenDevices();

    private static final boolean SOLO_UNA_PANTALLA = screens.length < 2;

    private static final int PUERTO = 7171;

    private static final int CACHE_MAX = 20;
    private static final Map<String, BufferedImage> CACHE = Collections.synchronizedMap(
        new LinkedHashMap<String, BufferedImage>(CACHE_MAX + 1, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<String, BufferedImage> eldest) {
                boolean remove = size() > CACHE_MAX;
                if (remove) eldest.getValue().flush();
                return remove;
            }
        }
    );

    // screen → (maskId → MaskData); reemplazado atómicamente por comando MASKS.
    private static final ConcurrentHashMap<String, ConcurrentHashMap<String, MaskData>> MASKS =
            new ConcurrentHashMap<>();

    private static final Properties CONFIG = loadConfig();

    private static Properties loadConfig() {
        Properties p = new Properties();
        p.setProperty("ruta.vid.pro1", "C:\\DataBase\\img y vid\\vid\\Pro1");
        p.setProperty("ruta.vid.pro2", "C:\\DataBase\\img y vid\\vid\\Pro2");
        p.setProperty("ruta.img.pro1", "C:\\DataBase\\img y vid\\img\\Pro1");
        p.setProperty("ruta.img.pro2", "C:\\DataBase\\img y vid\\img\\Pro2");
        p.setProperty("mpv.pipe.pro1", "mpv_pro1");
        p.setProperty("mpv.pipe.pro2", "mpv_pro2");
        File cfgFile = new File("config.properties");
        if (cfgFile.exists()) {
            try (InputStream in = new FileInputStream(cfgFile)) {
                p.load(in);
                System.out.println("[CONFIG] cargado desde " + cfgFile.getAbsolutePath());
            } catch (IOException e) {
                System.out.println("[CONFIG] ERROR leyendo config.properties: " + e.getMessage());
            }
        } else {
            System.out.println("[CONFIG] config.properties no encontrado, usando valores por defecto");
        }
        return p;
    }

    private static final String RUTA_VID_1 = CONFIG.getProperty("ruta.vid.pro1");
    private static final String RUTA_VID_2 = CONFIG.getProperty("ruta.vid.pro2");
    private static final String RUTA_IMG_1 = CONFIG.getProperty("ruta.img.pro1");
    private static final String RUTA_IMG_2 = CONFIG.getProperty("ruta.img.pro2");

    private static final Map<String, List<String>> RUTAS_POR_PANTALLA;
    static {
        Map<String, List<String>> m = new LinkedHashMap<>();
        m.put("Pro1", Arrays.asList(RUTA_VID_1, RUTA_IMG_1));
        m.put("Pro2", Arrays.asList(RUTA_VID_2, RUTA_IMG_2));
        RUTAS_POR_PANTALLA = Collections.unmodifiableMap(m);
    }

    private static ServerSocket serverSocket;
    private static volatile boolean running = true;

    private static ExecutorService clientPool =
            Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors() * 2);

    private static final ExecutorService imageLoaderPool =
            Executors.newFixedThreadPool(2);

    private static MpvClient mpv1 = new MpvClient(CONFIG.getProperty("mpv.pipe.pro1"));
    private static MpvClient mpv2 = new MpvClient(CONFIG.getProperty("mpv.pipe.pro2"));

    private static final ImageWindow imgWin1 = new ImageWindow("Pro1", screens[0]);
    private static final ImageWindow imgWin2 = SOLO_UNA_PANTALLA
            ? imgWin1
            : new ImageWindow("Pro2", screens[1]);

    private static final ConcurrentHashMap<String, ConcurrentHashMap<String, File>> index = new ConcurrentHashMap<>();

    static {
        for (Map.Entry<String, List<String>> e : RUTAS_POR_PANTALLA.entrySet()) {
            for (String ruta : e.getValue()) {
                buildIndex(e.getKey(), ruta);
            }
        }
    }

    public static void main(String[] args) {
        System.out.println("[SERVER] iniciado en puerto " + PUERTO);

        GraphicsEnvironment ge = GraphicsEnvironment.getLocalGraphicsEnvironment();
        System.out.println("[SWING] GraphicsEnvironment headless: " + ge.isHeadless());
        GraphicsDevice[] devs = ge.getScreenDevices();
        System.out.println("[SWING] Pantallas detectadas: " + devs.length);
        for (int i = 0; i < devs.length; i++) {
            DisplayMode dm = devs[i].getDisplayMode();
            System.out.println("[SWING]   Pantalla[" + i + "]: "
                    + dm.getWidth() + "x" + dm.getHeight()
                    + " ID=" + devs[i].getIDstring());
        }

        if (SOLO_UNA_PANTALLA) {
            System.out.println("[SWING] Solo hay una pantalla: Pro1 y Pro2 usaran una unica ventana");
        }

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("[SHUTDOWN] cerrando recursos...");
            running = false;
            try { if (serverSocket != null) serverSocket.close(); } catch (Exception ignored) {}
            clientPool.shutdownNow();
            mpv1.shutdown();
            mpv2.shutdown();
            System.out.println("[SHUTDOWN] recursos liberados");
        }, "shutdown-hook"));

        startFileWatcher();
        startServer();
    }

    private static void startServer() {
        try {
            serverSocket = new ServerSocket(PUERTO);
            serverSocket.setSoTimeout(2000);
            System.out.println("[SERVER] esperando conexiones...");

            while (running) {
                try {
                    Socket client = serverSocket.accept();
                    System.out.println("[SERVER] cliente conectado: " + client.getInetAddress());
                    clientPool.execute(new ClientHandler(client));
                } catch (SocketTimeoutException ignored) {
                }
            }
        } catch (Exception e) {
            System.out.println("[SERVER] ERROR en startServer:");
            e.printStackTrace();
        }
    }

    static void restart() {
        System.out.println("[RESTART] iniciando reinicio...");

        running = false;

        try {
            if (serverSocket != null && !serverSocket.isClosed()) {
                serverSocket.close();
            }
        } catch (Exception ignored) {}

        clientPool.shutdownNow();
        try { clientPool.awaitTermination(3, TimeUnit.SECONDS); } catch (InterruptedException ignored) {}
        mpv1.shutdown();
        mpv2.shutdown();

        CACHE.clear();
        imgWin1.reset();
        if (imgWin2 != imgWin1) {
            imgWin2.reset();
        }

        for (String screen : RUTAS_POR_PANTALLA.keySet()) {
            rebuildScreenIndex(screen);
        }

        clientPool = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors() * 2);
        mpv1.reinit();
        mpv2.reinit();

        running = true;

        new Thread(Main::startServer, "server-main").start();

        System.out.println("[RESTART] reinicio completado");
    }

    private static void rebuildScreenIndex(String screen) {
        List<String> rutas = RUTAS_POR_PANTALLA.get(screen);
        if (rutas == null) return;
        ConcurrentHashMap<String, File> newMap = new ConcurrentHashMap<>();
        for (String ruta : rutas) {
            File dir = new File(ruta);
            if (!dir.isDirectory() || !dir.canRead()) continue;
            File[] files = dir.listFiles((d, name) -> {
                String n = name.toLowerCase();
                return n.endsWith(".mp4") || n.endsWith(".mkv") || n.endsWith(".avi")
                    || n.endsWith(".mov") || n.endsWith(".webm")
                    || n.endsWith(".png") || n.endsWith(".jpg") || n.endsWith(".jpeg")
                    || n.endsWith(".bmp");
            });
            if (files != null) {
                for (File f : files) newMap.put(f.getName().toLowerCase(), f);
            }
        }
        index.put(screen, newMap);
        System.out.println("[INDEX] reconstruido -> " + screen + " (" + newMap.size() + " archivos)");
    }

    private static void startFileWatcher() {
        Thread t = new Thread(() -> {
            try (WatchService ws = FileSystems.getDefault().newWatchService()) {
                Map<WatchKey, String> keyScreen = new HashMap<>();
                for (Map.Entry<String, List<String>> e : RUTAS_POR_PANTALLA.entrySet()) {
                    for (String ruta : e.getValue()) {
                        try {
                            Path p = Paths.get(ruta);
                            if (Files.isDirectory(p)) {
                                WatchKey k = p.register(ws,
                                    StandardWatchEventKinds.ENTRY_CREATE,
                                    StandardWatchEventKinds.ENTRY_DELETE,
                                    StandardWatchEventKinds.ENTRY_MODIFY);
                                keyScreen.put(k, e.getKey());
                                System.out.println("[WATCHER] vigilando -> " + ruta);
                            }
                        } catch (IOException ex) {
                            System.out.println("[WATCHER] no se pudo registrar -> " + ruta + ": " + ex.getMessage());
                        }
                    }
                }
                while (running) {
                    WatchKey key = ws.poll(2, TimeUnit.SECONDS);
                    if (key == null) continue;
                    String screen = keyScreen.get(key);
                    if (screen != null && !key.pollEvents().isEmpty()) {
                        System.out.println("[WATCHER] cambio detectado en -> " + screen);
                        rebuildScreenIndex(screen);
                    }
                    if (!key.reset()) {
                        System.out.println("[WATCHER] directorio no disponible, deteniendo vigía");
                        break;
                    }
                }
            } catch (Exception e) {
                System.out.println("[WATCHER] error: " + e.getMessage());
            }
        }, "file-watcher");
        t.setDaemon(true);
        t.start();
    }

    private static void buildIndex(String screen, String ruta) {
        System.out.println("[INDEX] escaneando -> " + ruta);

        File dir = new File(ruta);
        if (!dir.exists())      { System.out.println("[INDEX] ERROR: no existe -> " + ruta); return; }
        if (!dir.isDirectory()) { System.out.println("[INDEX] ERROR: no es directorio -> " + ruta); return; }
        if (!dir.canRead())     { System.out.println("[INDEX] ERROR: sin lectura -> " + ruta); return; }

        File[] files = dir.listFiles((d, name) -> {
            String n = name.toLowerCase();
            return n.endsWith(".mp4") || n.endsWith(".mkv") || n.endsWith(".avi")
                || n.endsWith(".mov") || n.endsWith(".webm")
                || n.endsWith(".png") || n.endsWith(".jpg") || n.endsWith(".jpeg")
                || n.endsWith(".bmp");
        });

        ConcurrentHashMap<String, File> map = index.computeIfAbsent(screen, k -> new ConcurrentHashMap<>());
        if (files != null) {
            for (File f : files) {
                map.put(f.getName().toLowerCase(), f);
                System.out.println("[INDEX]   + " + f.getName());
            }
        } else {
            System.out.println("[INDEX] WARNING: listFiles() devolvio null en " + ruta);
        }
        System.out.println("[INDEX] cargado -> " + screen + " (" + map.size() + " archivos total)");
    }

    static class ClientHandler implements Runnable {

        private final Socket socket;

        ClientHandler(Socket socket) {
            this.socket = socket;
        }

        @Override
        public void run() {
            try { socket.setSoTimeout(30_000); } catch (Exception ignored) {}
            try (
                BufferedReader in  = new BufferedReader(new InputStreamReader(socket.getInputStream()));
                PrintWriter    out = new PrintWriter(socket.getOutputStream(), true)
            ) {
                String line;
                while ((line = in.readLine()) != null) {
                    System.out.println("[CMD] recibido: '" + line.trim() + "'");
                    String resp = process(line.trim());
                    System.out.println("[CMD] respuesta: " + resp);
                    out.println(resp);
                }
            } catch (Exception e) {
                System.out.println("[CLIENT] desconectado: " + e.getMessage());
            }
        }

        private String process(String msg) {
            String[] p = msg.split(" ");
            System.out.println("[PROCESS] partes: " + Arrays.toString(p));

            if (p.length < 1) {
                System.out.println("[PROCESS] ERROR: mensaje vacio");
                return "ERROR";
            }

            String first = p[0];

            if (first.equalsIgnoreCase("restart")) {
                System.out.println("[PROCESS] comando restart recibido");
                new Thread(Main::restart, "restart-thread").start();
                return "RESTARTING";
            }

            if (p.length < 2) {
                System.out.println("[PROCESS] ERROR: mensaje muy corto");
                return "ERROR";
            }

            String screen = p[0];
            String cmd    = p[1];
            System.out.println("[PROCESS] screen='" + screen + "' cmd='" + cmd + "'");

            MpvClient   mpv    = screen.equals("Pro1") ? mpv1    : mpv2;
            ImageWindow imgWin = screen.equals("Pro1") ? imgWin1 : imgWin2;

            if (cmd.equalsIgnoreCase("status")) {
                boolean hdmi1 = screens.length >= 1;
                boolean hdmi2 = screens.length >= 2;
                return "{\"hdmi1\":" + hdmi1 + ",\"hdmi2\":" + hdmi2 + "}";
            }

            if (cmd.equalsIgnoreCase("clear_masks")) {
                MASKS.put(screen, new ConcurrentHashMap<>());
                imgWin.repaintMasks(Collections.emptyList());
                return "OK";
            }

            // MASKS <origW>,<origH>;<id,x,y,w,h,type[:shape,x,y,w,h~shape,x,y,w,h~...]|id2,...>
            // — actualización atómica de todas las máscaras. La cabecera
            // "<origW>,<origH>;" es opcional (mensajes antiguos sin cabecera).
            // La parte tras ":" son las formas transparentes recortadas sobre
            // un donut (type==2) — cero o más, separadas por "~"; el resto de
            // formas nunca la llevan.
            if (cmd.equalsIgnoreCase("masks")) {
                ConcurrentHashMap<String, MaskData> maskMap = new ConcurrentHashMap<>();
                int hdrW = -1, hdrH = -1;
                if (p.length > 2) {
                    String payload = p[2];
                    String maskList = payload;
                    int semi = payload.indexOf(';');
                    if (semi >= 0) {
                        String[] hw = payload.substring(0, semi).split(",");
                        if (hw.length == 2) {
                            try {
                                hdrW = Integer.parseInt(hw[0]);
                                hdrH = Integer.parseInt(hw[1]);
                            } catch (NumberFormatException ignored) {}
                        }
                        maskList = payload.substring(semi + 1);
                    }
                    if (!maskList.isEmpty()) {
                        for (String part : maskList.split("\\|")) {
                            String core = part;
                            List<MaskCutout> cutouts = new ArrayList<>();
                            int colon = part.indexOf(':');
                            if (colon >= 0) {
                                core = part.substring(0, colon);
                                String cutoutBlob = part.substring(colon + 1);
                                if (!cutoutBlob.isEmpty()) {
                                    for (String cpart : cutoutBlob.split("~")) {
                                        String[] cf = cpart.split(",");
                                        if (cf.length < 5) continue;
                                        try {
                                            cutouts.add(new MaskCutout(
                                                Integer.parseInt(cf[0]), Integer.parseInt(cf[1]),
                                                Integer.parseInt(cf[2]), Integer.parseInt(cf[3]),
                                                Integer.parseInt(cf[4])));
                                        } catch (NumberFormatException ignored) {}
                                    }
                                }
                            }
                            String[] f = core.split(",");
                            if (f.length < 6) continue;
                            try {
                                maskMap.put(f[0], new MaskData(f[0],
                                    Integer.parseInt(f[1]), Integer.parseInt(f[2]),
                                    Integer.parseInt(f[3]), Integer.parseInt(f[4]),
                                    Integer.parseInt(f[5]), cutouts));
                            } catch (NumberFormatException ignored) {}
                        }
                    }
                }
                MASKS.put(screen, maskMap);
                imgWin.repaintMasks(new ArrayList<>(maskMap.values()), hdrW, hdrH);
                return "OK";
            }

            ConcurrentHashMap<String, File> map = index.get(screen);
            if (map == null) {
                System.out.println("[PROCESS] ERROR: screen no encontrada -> '" + screen + "'");
                return "ERROR_SCREEN";
            }

            String cmdLower = cmd.toLowerCase();
            File video = map.get(cmdLower);
            if (video == null) {
                video = map.values().stream()
                        .filter(f -> f.getName().toLowerCase().startsWith(cmdLower))
                        .findFirst().orElse(null);
            }

            if (video == null) {
                System.out.println("[PROCESS] ERROR: archivo no encontrado -> '" + cmd + "'");
                map.keySet().forEach(k -> System.out.println("[PROCESS]   - " + k));
                return "NO_VIDEO";
            }

            System.out.println("[PROCESS] encontrado -> " + video.getAbsolutePath());

            String path  = video.getAbsolutePath();
            String lower = path.toLowerCase();
            boolean esImagen = lower.endsWith(".png") || lower.endsWith(".jpg")
                            || lower.endsWith(".jpeg") || lower.endsWith(".bmp");

            System.out.println("[PROCESS] tipo: " + (esImagen ? "IMAGEN" : "VIDEO"));

            if (esImagen) {
                imgWin.showImage(path);
            } else {
                imgWin.hide();
                mpv.play(path);
            }

            System.out.println("[PLAY] " + screen + " -> " + video.getName());
            return "OK";
        }
    }

    static class ImageWindow {

        private final String         screenName;
        private final GraphicsDevice screen;
        private volatile String      lastRequestedPath = null;
        private JFrame               frame;
        private ImagePanel           panel;

        ImageWindow(String screenName, GraphicsDevice screen) {
            this.screenName = screenName;
            this.screen     = screen;
            // El frame se crea al inicio para que las mascaras funcionen desde
            // el primer momento, incluso antes de mostrar cualquier imagen.
            SwingUtilities.invokeLater(this::createFrame);
        }

        public void showImage(String filePath) {
            if (filePath.equals(lastRequestedPath)) return;
            lastRequestedPath = filePath;

            System.out.println("[IMG_WIN:" + screenName + "] solicitud -> " + filePath);

            imageLoaderPool.execute(() -> {
                if (!filePath.equals(lastRequestedPath)) {
                    System.out.println("[IMG_WIN:" + screenName + "] descartada -> " + filePath);
                    return;
                }

                BufferedImage img = loadCached(filePath);

                SwingUtilities.invokeLater(() -> {
                    try {
                        createFrame();
                        panel.setImageMode(true);
                        panel.setImage(img);
                        if (!frame.isVisible()) frame.setVisible(true);
                        System.out.println("[IMG_WIN:" + screenName + "] imagen mostrada");
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                });
            });
        }

        // Cambia a modo transparente: el frame sigue visible como overlay sobre mpv.
        // Las mascaras siguen siendo visibles sobre el video.
        public void hide() {
            System.out.println("[IMG_WIN:" + screenName + "] modo video (overlay transparente)");
            lastRequestedPath = null;
            SwingUtilities.invokeLater(() -> {
                if (panel != null) {
                    panel.setImageMode(false);
                    panel.setImage(null);
                }
            });
        }

        public void repaintMasks(List<MaskData> masks) {
            repaintMasks(masks, -1, -1);
        }

        // srcW/srcH: dimensiones (px) de la imagen/vídeo fuente que el cliente usó para
        // calcular las coordenadas de las máscaras. -1 = sin cabecera en este mensaje,
        // mantener las últimas dimensiones conocidas.
        public void repaintMasks(List<MaskData> masks, int srcW, int srcH) {
            SwingUtilities.invokeLater(() -> {
                createFrame();
                if (panel != null) panel.setMasks(masks, srcW, srcH);
            });
        }

        public void reset() {
            lastRequestedPath = null;
            SwingUtilities.invokeLater(() -> {
                if (frame != null) {
                    frame.dispose();
                    frame = null;
                    panel = null;
                    System.out.println("[IMG_WIN:" + screenName + "] frame destruido en reset");
                }
            });
        }

        private void createFrame() {
            if (frame != null) return;
            System.out.println("[IMG_WIN:" + screenName + "] creando JFrame...");
            frame = new JFrame("IMG_" + screenName);
            frame.setUndecorated(true);
            frame.setAlwaysOnTop(true);
            // Fondo transparente: en modo video el frame actua como overlay sobre mpv.
            frame.setBackground(new Color(0, 0, 0, 0));
            frame.setDefaultCloseOperation(JFrame.HIDE_ON_CLOSE);
            panel = new ImagePanel();
            frame.add(panel);
            frame.setBounds(screen.getDefaultConfiguration().getBounds());
            frame.setVisible(true);
            System.out.println("[IMG_WIN:" + screenName + "] frame creado y visible");
        }

        private static BufferedImage loadCached(String path) {
            synchronized (CACHE) {
                BufferedImage cached = CACHE.get(path);
                if (cached != null) return cached;
            }
            try {
                BufferedImage loaded = ImageIO.read(new File(path));
                if (loaded == null) return null;
                synchronized (CACHE) {
                    BufferedImage existing = CACHE.get(path);
                    if (existing != null) {
                        loaded.flush();
                        return existing;
                    }
                    CACHE.put(path, loaded);
                    return loaded;
                }
            } catch (IOException e) {
                System.out.println("[CACHE] ERROR leyendo imagen: " + e.getMessage());
                return null;
            }
        }
    }

    static class ImagePanel extends JPanel {

        // Imagen pre-escalada al tamaño exacto del panel, formato display-compatible.
        // paintComponent hace solo un blit directo — sin escalado en cada repintado.
        private volatile BufferedImage scaledImage;

        // Dimensiones originales de la imagen fuente, usadas solo para escalar el blit
        // de la imagen de fondo (buildScaled). No se usan para posicionar máscaras.
        private int origImgW = 1;
        private int origImgH = 1;

        // Dimensiones (px) de la imagen/vídeo fuente que el cliente usó para calcular las
        // coordenadas de las máscaras — llegan en cada mensaje MASKS y son independientes
        // de origImgW/origImgH, así que también son válidas en modo vídeo (donde no hay
        // ninguna imagen cargada localmente). 0 = aún desconocidas.
        private volatile int maskSrcW = 0;
        private volatile int maskSrcH = 0;

        private volatile List<MaskData> masks = Collections.emptyList();
        // false = transparente (video/solo mascaras); true = opaco (imagen + mascaras)
        private boolean imageMode = false;

        ImagePanel() {
            setBackground(Color.BLACK);
            setDoubleBuffered(true);
            setOpaque(false); // arranca transparente hasta que se muestre una imagen
        }

        // Llamado desde EDT cuando se cambia entre imagen y video.
        public void setImageMode(boolean imageMode) {
            this.imageMode = imageMode;
            setOpaque(imageMode);
            repaint();
        }

        // Llamado desde EDT. src es la imagen full-res del cache.
        public void setImage(BufferedImage src) {
            if (src == null) {
                scaledImage = null;
                repaint();
                return;
            }
            origImgW = src.getWidth();
            origImgH = src.getHeight();
            int pw = getWidth();
            int ph = getHeight();
            scaledImage = (pw > 0 && ph > 0) ? buildScaled(src, pw, ph) : src;
            repaint();
        }

        public void setMasks(List<MaskData> ms, int srcW, int srcH) {
            this.masks = ms;
            if (srcW > 0 && srcH > 0) {
                this.maskSrcW = srcW;
                this.maskSrcH = srcH;
            }
            repaint();
        }

        @Override
        protected void paintComponent(Graphics g) {
            int pw = getWidth();
            int ph = getHeight();
            if (pw <= 0 || ph <= 0) return;

            // En modo imagen: super pinta el fondo negro.
            // En modo transparente (video): no pintamos fondo — el frame es transparente
            // y las mascaras se ven como formas negras flotando sobre mpv.
            if (imageMode) super.paintComponent(g);

            BufferedImage img = scaledImage;
            if (img != null) {
                if (img.getWidth() != pw || img.getHeight() != ph) {
                    img = buildScaled(img, pw, ph);
                    scaledImage = img;
                }
                g.drawImage(img, 0, 0, null);
            }

            List<MaskData> ms = this.masks;
            if (!ms.isEmpty() && maskSrcW > 0 && maskSrcH > 0) {
                Graphics2D g2 = (Graphics2D) g;
                g2.setColor(Color.BLACK);
                double sc = Math.max((double) pw / maskSrcW, (double) ph / maskSrcH);
                double ox = (pw - maskSrcW * sc) / 2.0;
                double oy = (ph - maskSrcH * sc) / 2.0;
                for (MaskData m : ms) {
                    int sx = (int) (ox + m.x * sc);
                    int sy = (int) (oy + m.y * sc);
                    int sw = Math.max(1, (int) (m.w * sc));
                    int sh = Math.max(1, (int) (m.h * sc));
                    if (m.type == 0) {
                        g2.fillOval(sx, sy, sw, sh);
                    } else if (m.type == 1) {
                        g2.fillRect(sx, sy, sw, sh);
                    } else if (m.type == 2) {
                        // Donut: rectángulo negro con cada forma transparente
                        // recortada de forma independiente (m.cutouts).
                        Area donutArea = new Area(new Rectangle2D.Double(sx, sy, sw, sh));
                        for (MaskCutout c : m.cutouts) {
                            int isx = (int) (ox + c.x * sc);
                            int isy = (int) (oy + c.y * sc);
                            int isw = Math.max(1, (int) (c.w * sc));
                            int ish = Math.max(1, (int) (c.h * sc));
                            donutArea.subtract(new Area(shapeFor(c.shape, isx, isy, isw, ish)));
                        }
                        g2.fill(donutArea);
                    } else if (m.type == 3) {
                        int[] xs = {sx + sw / 2, sx + sw, sx};
                        int[] ys = {sy, sy + sh, sy + sh};
                        g2.fillPolygon(xs, ys, 3);
                    }
                }
            }
        }

        // Escala 'src' con cover-fill al tamaño pw×ph y convierte al formato
        // nativo de la GPU para que los blits en paintComponent sean instantaneos.
        private BufferedImage buildScaled(BufferedImage src, int pw, int ph) {
            int iw = src.getWidth();
            int ih = src.getHeight();
            double scale = Math.max((double) pw / iw, (double) ph / ih);
            int dw = Math.max(1, (int) (iw * scale));
            int dh = Math.max(1, (int) (ih * scale));
            int x  = (pw - dw) / 2;
            int y  = (ph - dh) / 2;

            GraphicsConfiguration gc = getGraphicsConfiguration();
            if (gc == null) {
                gc = GraphicsEnvironment.getLocalGraphicsEnvironment()
                         .getDefaultScreenDevice().getDefaultConfiguration();
            }
            BufferedImage out = gc.createCompatibleImage(pw, ph, Transparency.OPAQUE);
            Graphics2D g2 = out.createGraphics();
            g2.setColor(Color.BLACK);
            g2.fillRect(0, 0, pw, ph);
            g2.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                                RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            g2.drawImage(src, x, y, dw, dh, null);
            g2.dispose();
            return out;
        }
    }

    // Construye la forma geométrica correspondiente a un índice de MaskType
    // (0=circulo,1=cuadrado,3=triangulo) — usado tanto para las formas
    // principales como para las formas transparentes recortadas del donut.
    private static Shape shapeFor(int shape, int x, int y, int w, int h) {
        if (shape == 1) {
            return new Rectangle2D.Double(x, y, w, h);
        } else if (shape == 3) {
            int[] xs = {x + w / 2, x + w, x};
            int[] ys = {y, y + h, y + h};
            return new Polygon(xs, ys, 3);
        }
        return new Ellipse2D.Double(x, y, w, h);
    }

    // Forma transparente independiente recortada sobre un donut (solo type == 2):
    // shape sigue el mismo índice que MaskType en el cliente (0=circulo,1=cuadrado,3=triangulo).
    static class MaskCutout {
        final int shape, x, y, w, h;
        MaskCutout(int shape, int x, int y, int w, int h) {
            this.shape = shape; this.x = x; this.y = y; this.w = w; this.h = h;
        }
    }

    static class MaskData {
        final String id;
        final int x, y, w, h, type;
        // Solo se usa para type == 2 (donut): formas transparentes recortadas
        // sobre el rectángulo negro, cada una independiente. Vacía para el
        // resto de tipos.
        final List<MaskCutout> cutouts;
        MaskData(String id, int x, int y, int w, int h, int type, List<MaskCutout> cutouts) {
            this.id = id; this.x = x; this.y = y; this.w = w; this.h = h; this.type = type;
            this.cutouts = cutouts;
        }
    }

    static class MpvClient {

        private final String pipeName;
        private OutputStream out;
        private final AtomicReference<String> latestFile = new AtomicReference<>(null);
        private ExecutorService mpvExecutor;

        MpvClient(String pipeName) {
            this.pipeName    = pipeName;
            this.mpvExecutor = createExecutor();
        }

        private ExecutorService createExecutor() {
            return Executors.newSingleThreadExecutor(r -> {
                Thread t = new Thread(r, "mpv-writer-" + pipeName);
                t.setDaemon(true);
                return t;
            });
        }

        public void shutdown() {
            mpvExecutor.shutdownNow();
            try { if (out != null) out.close(); } catch (Exception ignored) {}
            out = null;
        }

        public void reinit() {
            latestFile.set(null);
            mpvExecutor = createExecutor();
        }

        private boolean connect() {
            try {
                String pipePath = "\\\\.\\pipe\\" + pipeName;
                System.out.println("[MPV:" + pipeName + "] conectando a " + pipePath);
                out = new FileOutputStream(pipePath);
                System.out.println("[MPV:" + pipeName + "] conectado OK");
                return true;
            } catch (Exception e) {
                System.out.println("[MPV:" + pipeName + "] no disponible: " + e.getMessage());
                out = null;
                return false;
            }
        }

        public void play(String file) {
            System.out.println("[MPV:" + pipeName + "] solicitando -> " + file);
            latestFile.set(file);
            mpvExecutor.execute(this::drainLatest);
        }

        // El executor es single-thread: si llegan N llamadas rapidas a play(),
        // el primer drainLatest que corra lee el ultimo archivo (getAndSet), los
        // siguientes encuentran null y terminan inmediatamente. Solo se envia 1 comando.
        private void drainLatest() {
            String file = latestFile.getAndSet(null);
            if (file != null) sendToMpv(file);
        }

        private void sendToMpv(String file) {
            try {
                if (out == null && !connect()) {
                    System.out.println("[MPV:" + pipeName + "] sin conexion, descartando -> " + file);
                    return;
                }

                String cmd = "{ \"command\": [\"loadfile\", \""
                        + file.replace("\\", "\\\\")
                        + "\", \"replace\"] }\n";

                System.out.println("[MPV:" + pipeName + "] enviando: " + cmd.trim());
                out.write(cmd.getBytes());
                out.flush();
                System.out.println("[MPV:" + pipeName + "] enviado OK");

            } catch (Exception e) {
                System.out.println("[MPV:" + pipeName + "] ERROR, reconectando: " + e.getMessage());
                try { if (out != null) out.close(); } catch (Exception ignored) {}
                out = null;
            }
        }
    }
}