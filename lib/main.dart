import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi' hide Size;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:window_manager/window_manager.dart';

// ==========================================
// 1. HARDWARE DETECTION
// ==========================================

enum GraphicsMode { highEnd, vm }

class HardwareDetector {
  static Future<GraphicsMode> detect() async {
    try {
      final vendor = await _readFile('/sys/class/dmi/id/sys_vendor');
      final product = await _readFile('/sys/class/dmi/id/product_name');
      final combined = '$vendor $product'.toLowerCase();

      if (combined.contains('qemu') ||
        combined.contains('kvm') ||
        combined.contains('virtualbox') ||
        combined.contains('vmware') ||
        combined.contains('innotek')) {
        return GraphicsMode.vm;
        }

        final lspci = await Process.run('lspci', []);
      if (lspci.exitCode == 0) {
        if (lspci.stdout.toString().toLowerCase().contains('virtio gpu')) {
          return GraphicsMode.vm;
        }
      }
      return GraphicsMode.highEnd;
    } catch (e) {
      return GraphicsMode.vm;
    }
  }

  static Future<String> _readFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) return (await file.readAsString()).trim();
    } catch (_) {}
    return '';
  }
}

late GraphicsMode globalGraphicsMode;

// ==========================================
// 2. CONSOLE MANAGER
// ==========================================

class ConsoleManager extends ChangeNotifier {
  static final ConsoleManager _instance = ConsoleManager._internal();
  factory ConsoleManager() => _instance;
  ConsoleManager._internal();

  List<String> logs = [];
  bool isVisible = false;
  bool isRunning = false;
  Process? _activeProcess;
  final ScrollController scrollController = ScrollController();

  void toggle(bool show) {
    isVisible = show;
    notifyListeners();
  }

  void addLog(String log) {
    logs.add(log);
    notifyListeners();
    // Auto-scroll to bottom after render
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> runCommand(String command, {bool sudo = false}) async {
    if (isRunning) return;
    logs.clear();
    isVisible = true;
    isRunning = true;
    notifyListeners();

    String executable = 'bash';
    List<String> args = ['-c', command];
    if (sudo) {
      executable = 'pkexec';
      args = ['bash', '-c', command];
    }

    addLog("\$ $command");

    try {
      _activeProcess = await Process.start(executable, args);
      _activeProcess!.stdout.transform(utf8.decoder).listen((data) {
        for (var line in LineSplitter.split(data)) addLog(line);
      });
        _activeProcess!.stderr.transform(utf8.decoder).listen((data) {
          for (var line in LineSplitter.split(data)) addLog("[ERR] $line");
        });

          int exitCode = await _activeProcess!.exitCode;
          addLog("\n>> EXIT CODE: $exitCode");

    } catch (e) {
      addLog(">> ERROR: $e");
    } finally {
      isRunning = false;
      _activeProcess = null;
      notifyListeners();
    }
  }

  void killProcess() {
    _activeProcess?.kill();
    addLog(">> Process Killed.");
    isRunning = false;
    notifyListeners();
  }
}

// ==========================================
// 3. SYSTEM HELPERS & MAIN
// ==========================================

void fixLinuxLocale() {
  if (!Platform.isLinux) return;
  try {
    final libc = DynamicLibrary.open('libc.so.6');
    final setlocale = libc.lookupFunction<
    Pointer<Utf8> Function(Int32, Pointer<Utf8>),
    Pointer<Utf8> Function(int, Pointer<Utf8>)>('setlocale');
    final cString = 'C'.toNativeUtf8();
    setlocale(1, cString);
  } catch (e) {
    debugPrint("Failed to set locale: $e");
  }
}

String getAssetPath(String asset) {
  return 'asset:///$asset';
}

Future<void> main() async {
  fixLinuxLocale();
  globalGraphicsMode = await HardwareDetector.detect();

  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  // VM = Black (Artifact prevention)
  // Real = Transparent
  Color winBg = (globalGraphicsMode == GraphicsMode.vm) ? Colors.black : Colors.transparent;

  WindowOptions windowOptions = WindowOptions(
    size: const Size(1280, 720),
    center: true,
    backgroundColor: winBg,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: "BAL Helper",
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const BlueArchiveLinuxApp());
}

class AppTheme {
  static const Color primaryBlue = Color(0xFF128CFF);
  static const Color primaryDark = Color(0xFF0D65B8);
  static const Color haloPink = Color(0xFFFF9FF3);
  static const Color haloYellow = Color(0xFFFDCB6E);
  static const Color darkText = Color(0xFF2D3436);
}

class BlueArchiveLinuxApp extends StatelessWidget {
  const BlueArchiveLinuxApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blue Archive Linux',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: GoogleFonts.rubikTextTheme(),
        iconTheme: const IconThemeData(color: AppTheme.primaryBlue),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final Player _player;
  late final VideoController _controller;
  int _currentViewIndex = 0;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error));

    // Check mode
    final bool isVm = globalGraphicsMode == GraphicsMode.vm;

    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        // Force software decoding on VMs to fix Virtio crash
        hwdec: isVm ? 'no' : 'auto',
      ),
    );

    final videoPath = getAssetPath('assets/video/bg_loop.mp4');
    _player.open(Media(videoPath));
    _player.setPlaylistMode(PlaylistMode.loop);
    _player.setVolume(0.0);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _navigateTo(int index) => setState(() => _currentViewIndex = index);

  @override
  Widget build(BuildContext context) {
    Widget activeWidget;
    switch (_currentViewIndex) {
      case 0: activeWidget = WelcomeView(onNext: () => _navigateTo(1)); break;
      case 1: activeWidget = DashboardView(onNavigate: _navigateTo, onExit: () => exit(0)); break;
      case 2: activeWidget = LogisticsView(onBack: () => _navigateTo(1)); break;
      case 3: activeWidget = VisualsView(onBack: () => _navigateTo(1)); break;
      case 4: activeWidget = MaintenanceView(onBack: () => _navigateTo(1)); break;
      default: activeWidget = Container();
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. Video Background
          SizedBox.expand(child: Video(controller: _controller, fit: BoxFit.cover, controls: NoVideoControls)),

          // 2. White Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.97),
                  Colors.white.withOpacity(0.9),
                  Colors.white.withOpacity(0.4),
                  Colors.transparent
                ],
                stops: const [0.0, 0.3, 0.8, 1.0],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),

          // 3. Grid Pattern
          Positioned.fill(child: CustomPaint(painter: GridPainter())),

          // 4. Main Content Area
          Padding(
            padding: const EdgeInsets.only(top: 40.0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOutExpo,
                switchOutCurve: Curves.easeInExpo,
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.05, 0.0), end: Offset.zero).animate(anim), child: child)),
                  child: KeyedSubtree(key: ValueKey<int>(_currentViewIndex), child: activeWidget),
            ),
          ),

          // 5. Console Overlay
          const ConsoleOverlay(),

          // 6. Window Bar
          const Positioned(
            top: 0, left: 0, right: 0, height: 40,
            child: CustomTitleBar(),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// CUSTOM TITLE BAR
// ==========================================
class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DragToMoveArea(child: ColoredBox(color: Colors.transparent)),
        ),
        Positioned(
          top: 0, bottom: 0, left: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TrafficLightButton(color: const Color(0xFFFF5F57), onTap: () => windowManager.close(), icon: Icons.close),
              const SizedBox(width: 8),
              _TrafficLightButton(color: const Color(0xFFFFBD2E), onTap: () => windowManager.minimize(), icon: Icons.remove),
              const SizedBox(width: 8),
              _TrafficLightButton(color: const Color(0xFF28C840), onTap: () async { if (await windowManager.isMaximized()) { windowManager.unmaximize(); } else { windowManager.maximize(); } }, icon: Icons.crop_square),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrafficLightButton extends StatefulWidget {
  final Color color; final VoidCallback onTap; final IconData icon;
  const _TrafficLightButton({required this.color, required this.onTap, required this.icon});
  @override State<_TrafficLightButton> createState() => _TrafficLightButtonState();
}

class _TrafficLightButtonState extends State<_TrafficLightButton> {
  bool _isHovered = false;
  @override Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 14, height: 14,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 1, offset: const Offset(0, 1))]),
          alignment: Alignment.center,
          child: _isHovered ? Icon(widget.icon, size: 9, color: Colors.black.withOpacity(0.6)) : null,
        ),
      ),
    );
  }
}

// ==========================================
// CONSOLE UI (FIXED COLORS)
// ==========================================
class ConsoleOverlay extends StatelessWidget {
  const ConsoleOverlay({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConsoleManager(),
      builder: (context, _) {
        final cm = ConsoleManager();
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          bottom: cm.isVisible ? 0 : -350,
          left: 0, right: 0, height: 320,
          child: Container(
            decoration: BoxDecoration(
              // Dark grey background, standard modern terminal feel
              color: const Color(0xFF282C34).withOpacity(0.98),
              border: const Border(top: BorderSide(color: AppTheme.primaryBlue, width: 2)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, -5))]
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                color: const Color(0xFF21252B), // Toolbar darker
                child: Row(children: [
                  const Icon(Icons.terminal, color: Colors.white70, size: 16), const SizedBox(width: 8),
                  Text("SYSTEM TERMINAL", style: GoogleFonts.sourceCodePro(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (cm.isRunning) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue)),
                    const SizedBox(width: 10),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70, size: 20), onPressed: () => cm.toggle(false)),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  controller: cm.scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: cm.logs.length,
                  itemBuilder: (context, index) {
                    final log = cm.logs[index];
                    final isError = log.startsWith("[ERR]") || log.contains("ERROR:");
                    final isCommand = log.startsWith("\$");

                    Color textColor;
                    if (isCommand) {
                      textColor = Colors.cyanAccent; // User commands
                    } else if (isError) {
                      textColor = const Color(0xFFFF5555); // Errors
                    } else {
                      textColor = Colors.white; // Standard output
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(log, style: GoogleFonts.sourceCodePro(color: textColor, fontSize: 13))
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ==========================================
// VIEWS
// ==========================================

class DashboardView extends StatelessWidget {
  final Function(int) onNavigate;
  final VoidCallback onExit;
  const DashboardView({super.key, required this.onNavigate, required this.onExit});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(60.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeInDown(child: const HeaderTitle(title: "SCHALE OFFICE", subtitle: "System Management Dashboard")),
          const SizedBox(height: 40),
          Expanded(
            child: Row(
              children: [
                Expanded(child: FadeInUp(delay: const Duration(milliseconds: 200), child: DashboardCard(
                  title: "LOGISTICS", subtitle: "Install Packages", icon: Icons.inventory_2_outlined, color: AppTheme.primaryBlue, onTap: () => onNavigate(2),
                ))),
                const SizedBox(width: 20),
                Expanded(child: FadeInUp(delay: const Duration(milliseconds: 400), child: DashboardCard(
                  title: "ART CLUB", subtitle: "Wallpapers & Themes", icon: Icons.palette_outlined, color: AppTheme.haloPink, onTap: () => onNavigate(3),
                ))),
                const SizedBox(width: 20),
                Expanded(child: FadeInUp(delay: const Duration(milliseconds: 600), child: DashboardCard(
                  title: "ENGINEERING", subtitle: "System Update", icon: Icons.build_outlined, color: AppTheme.haloYellow, onTap: () => onNavigate(4),
                ))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LogisticsView extends StatelessWidget {
  final VoidCallback onBack;
  const LogisticsView({super.key, required this.onBack});
  @override
  Widget build(BuildContext context) {
    return ContentLayout(
      title: "LOGISTICS SUPPORT", subtitle: "Package Installation Protocols", onBack: onBack, accentColor: AppTheme.primaryBlue,
      children: [
        FadeInRight(delay: const Duration(milliseconds: 100), child: ActionRow(
          title: "AUR Helper (Yay-bin)",
          command: "cd \$HOME && sudo pacman -S --needed --noconfirm git base-devel && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si --noconfirm",
          description: "Installs yay-bin (Faster compilation).", btnColor: AppTheme.primaryBlue,
        )),
        FadeInRight(delay: const Duration(milliseconds: 200), child: ActionRow(
          title: "Graphic Drivers (Nvidia)", command: "pacman -S --noconfirm nvidia nvidia-utils nvidia-settings",
          description: "Proprietary drivers for Green Team GPU.", btnColor: AppTheme.primaryBlue, requiresRoot: true,
        )),
        FadeInRight(delay: const Duration(milliseconds: 300), child: ActionRow(
          title: "Gaming Protocol (Steam)", command: "pacman -S --noconfirm steam",
          description: "Standard entertainment module.", btnColor: AppTheme.primaryBlue, requiresRoot: true,
        )),
        FadeInRight(delay: const Duration(milliseconds: 400), child: ActionRow(
          title: "Audio Stack (Pipewire)", command: "pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa wireplumber",
          description: "Modern audio handling subsystem.", btnColor: AppTheme.primaryBlue, requiresRoot: true,
        )),
      ],
    );
  }
}

class VisualsView extends StatelessWidget {
  final VoidCallback onBack;
  const VisualsView({super.key, required this.onBack});
  @override
  Widget build(BuildContext context) {
    return ContentLayout(
      title: "ART DEPARTMENT", subtitle: "Desktop Customization", onBack: onBack, accentColor: AppTheme.haloPink,
      children: [
        FadeInUp(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 200, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.haloPink, width: 2)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.wallpaper, size: 50, color: AppTheme.haloPink), const SizedBox(height: 20),
                    SenseiButton(text: "RANDOM WALLPAPER", onPressed: () => ConsoleManager().runCommand("plasma-apply-wallpaperimage \$(find /usr/share/backgrounds -type f | shuf -n 1)"), isPrimary: true, icon: Icons.shuffle),
                  ]),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Container(
                  height: 200, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.haloPink, width: 2)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.settings_display, size: 50, color: AppTheme.haloPink), const SizedBox(height: 20),
                    SenseiButton(text: "OPEN SETTINGS", onPressed: () => Process.run('systemsettings', []), isPrimary: false, icon: Icons.settings),
                  ]),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}

class MaintenanceView extends StatelessWidget {
  final VoidCallback onBack;
  const MaintenanceView({super.key, required this.onBack});
  @override
  Widget build(BuildContext context) {
    return ContentLayout(
      title: "ENGINEERING CLUB", subtitle: "System Maintenance", onBack: onBack, accentColor: AppTheme.haloYellow,
      children: [
        FadeInRight(delay: const Duration(milliseconds: 100), child: ActionRow(title: "System Update", command: "pacman -Syu --noconfirm", description: "Full system synchronization and upgrade.", btnColor: AppTheme.haloYellow, requiresRoot: true)),
        FadeInRight(delay: const Duration(milliseconds: 200), child: ActionRow(title: "Clean Cache", command: "pacman -Sc --noconfirm", description: "Remove old packages to free space.", btnColor: AppTheme.haloYellow, requiresRoot: true)),
        FadeInRight(delay: const Duration(milliseconds: 300), child: ActionRow(title: "Remove Orphans", command: "pacman -Rns \$(pacman -Qtdq) --noconfirm", description: "Remove unused dependencies.", btnColor: AppTheme.haloYellow, requiresRoot: true)),
      ],
    );
  }
}

class WelcomeView extends StatefulWidget {
  final VoidCallback onNext;
  const WelcomeView({super.key, required this.onNext});
  @override State<WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<WelcomeView> {
  final List<String> _greetings = ["Hello", "こんにちは", "Xin chào", "안녕하세요", "Bonjour"];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if(mounted) setState(() { _index = (_index + 1) % _greetings.length; });
    });
  }
  @override void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.only(left: 80.0), // Padding kept left as requested
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeInLeft(duration: const Duration(milliseconds: 800), child: Container(width: 60, height: 6, color: AppTheme.primaryBlue)),
            const SizedBox(height: 30),
            SizedBox(
              height: 120,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                layoutBuilder: (c, p) => Stack(alignment: Alignment.centerLeft, children: [if(c!=null) c, ...p]),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(anim), child: child)),
                child: Text(_greetings[_index], key: ValueKey(_index), style: GoogleFonts.montserrat(fontSize: 90, fontWeight: FontWeight.w200, color: AppTheme.darkText, height: 1.0, letterSpacing: -2)),
              ),
            ),
            const SizedBox(height: 10),
            FadeInUp(delay: const Duration(milliseconds: 400), child: Text("Welcome to Blue Archive Linux", style: GoogleFonts.rubik(fontSize: 28, color: AppTheme.primaryBlue, fontWeight: FontWeight.w700, letterSpacing: 1.5))),
            const SizedBox(height: 60),
            FadeInUp(delay: const Duration(milliseconds: 700), child: SenseiButton(text: "CONNECT TO SCHALE", onPressed: widget.onNext, icon: Icons.login)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// SHARED COMPONENTS
// ==========================================

class ContentLayout extends StatelessWidget {
  final String title, subtitle;
  final VoidCallback onBack;
  final Color accentColor;
  final List<Widget> children;
  const ContentLayout({super.key, required this.title, required this.subtitle, required this.onBack, required this.accentColor, required this.children});
  @override Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(60.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_ios, color: AppTheme.darkText)),
            const SizedBox(width: 10),
            HeaderTitle(title: title, subtitle: subtitle, accentColor: accentColor),
          ]),
          const SizedBox(height: 40),
          Divider(color: accentColor.withOpacity(0.3)),
          const SizedBox(height: 20),
          Expanded(child: SingleChildScrollView(child: Column(children: children))),
        ],
      ),
    );
  }
}

class HeaderTitle extends StatelessWidget {
  final String title, subtitle;
  final Color accentColor;
  const HeaderTitle({super.key, required this.title, required this.subtitle, this.accentColor = AppTheme.primaryBlue});
  @override Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 5, height: 40, color: accentColor), const SizedBox(width: 15), Text(title, style: GoogleFonts.rubik(fontSize: 40, fontWeight: FontWeight.bold, color: AppTheme.darkText))]),
      Padding(padding: const EdgeInsets.only(left: 20.0), child: Text(subtitle, style: GoogleFonts.rubik(fontSize: 18, color: Colors.grey[600], letterSpacing: 1))),
    ]);
  }
}

class ActionRow extends StatelessWidget {
  final String title, command, description; final Color btnColor; final bool requiresRoot;
  const ActionRow({super.key, required this.title, required this.command, required this.description, required this.btnColor, this.requiresRoot = false});
  @override Widget build(BuildContext context) {
    return Container(margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: btnColor, width: 4))), child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.rubik(fontWeight: FontWeight.bold, fontSize: 18)), const SizedBox(height: 5),
        Text(description, style: GoogleFonts.rubik(color: Colors.grey[600], fontSize: 14)), const SizedBox(height: 10),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)), child: Text(command, style: GoogleFonts.sourceCodePro(fontSize: 12, color: AppTheme.primaryDark), maxLines: 1, overflow: TextOverflow.ellipsis))
      ])),
      const SizedBox(width: 10),
      SenseiButton(text: "EXECUTE", onPressed: () => ConsoleManager().runCommand(command, sudo: requiresRoot), isPrimary: false, icon: Icons.terminal),
    ]));
  }
}

class DashboardCard extends StatefulWidget {
  final String title, subtitle; final IconData icon; final Color color; final VoidCallback onTap;
  const DashboardCard({super.key, required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});
  @override State<DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<DashboardCard> {
  bool _isHovered = false;
  @override Widget build(BuildContext context) {
    return MouseRegion(cursor: SystemMouseCursors.click, onEnter: (_) => setState(() => _isHovered = true), onExit: (_) => setState(() => _isHovered = false), child: GestureDetector(onTap: widget.onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic, transform: Matrix4.identity()..scale(_isHovered ? 1.02 : 1.0), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _isHovered ? widget.color : Colors.grey.shade300, width: _isHovered ? 3 : 1), boxShadow: _isHovered ? [BoxShadow(color: widget.color.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))] : []), child: Stack(children: [
      Positioned(right: -20, bottom: -20, child: Icon(widget.icon, size: 150, color: widget.color.withOpacity(0.1))),
      Padding(padding: const EdgeInsets.all(24.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: widget.color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(widget.icon, color: widget.color, size: 30)), const Spacer(),
        Text(widget.title, style: GoogleFonts.rubik(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.darkText)), const SizedBox(height: 5),
        Text(widget.subtitle, style: GoogleFonts.rubik(fontSize: 14, color: Colors.grey[600])), const SizedBox(height: 20),
        Container(height: 2, width: 40, color: widget.color),
      ])),
    ]))));
  }
}

class SenseiButton extends StatefulWidget {
  final String text; final VoidCallback onPressed; final bool isPrimary; final IconData? icon;
  const SenseiButton({super.key, required this.text, required this.onPressed, this.isPrimary = false, this.icon});
  @override State<SenseiButton> createState() => _SenseiButtonState();
}

class _SenseiButtonState extends State<SenseiButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller; late Animation<double> _scaleAnimation; bool _isHovered = false;
  @override void initState() { super.initState(); _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100)); _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller); }
  @override Widget build(BuildContext context) {
    Color bg = widget.isPrimary ? AppTheme.primaryBlue : Colors.white; Color fg = widget.isPrimary ? Colors.white : AppTheme.primaryBlue;
    if (_isHovered) { bg = widget.isPrimary ? AppTheme.primaryDark : AppTheme.primaryBlue; fg = Colors.white; }
    return MouseRegion(cursor: SystemMouseCursors.click, onEnter: (_) => setState(() => _isHovered = true), onExit: (_) => setState(() => _isHovered = false), child: GestureDetector(onTapDown: (_) => _controller.forward(), onTapUp: (_) { _controller.reverse(); widget.onPressed(); }, onTapCancel: () => _controller.reverse(), child: ScaleTransition(scale: _scaleAnimation, child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18), decoration: BoxDecoration(color: bg, border: Border.all(color: AppTheme.primaryBlue, width: 2)), child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (widget.icon != null) ...[Icon(widget.icon, size: 20, color: fg), const SizedBox(width: 12)],
        Text(widget.text, style: GoogleFonts.rubik(color: fg, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1)),
    ])))));
  }
}

class GridPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.03)..strokeWidth = 1; const step = 40.0;
    for (double x = 0; x < size.width; x += step) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    for (double y = 0; y < size.height; y += step) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
