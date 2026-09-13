import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as timezone;
import 'core/app_state.dart';
import 'core/config.dart';
import 'core/local_store.dart';
import 'core/radio_controller.dart';
import 'core/widget_service.dart';
import 'features/account.dart';
import 'features/education.dart';
import 'features/home.dart';
import 'features/radio.dart';
import 'features/reading.dart';
import 'features/tasbih.dart';
import 'features/workspace.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  timezone.initializeTimeZones();
  final organisation = await Organisation.load();
  SupabaseClient? client;
  if (backendUrl.isNotEmpty && backendKey.isNotEmpty) {
    await Supabase.initialize(
      url: backendUrl,
      publishableKey: backendKey,
      authOptions: const FlutterAuthClientOptions(localStorage: SessionStore()),
    );
    client = Supabase.instance.client;
  }
  if (!kIsWeb) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'community.radio',
      androidNotificationChannelName: 'Radio playback',
      androidNotificationOngoing: true,
    );
  }
  final state = AppState(
    organisation,
    client,
    await SharedPreferences.getInstance(),
  );
  final radio = state.radio;
  runApp(CommunityApp(state, radio));
  unawaited(state.initialise());
}

class CommunityApp extends StatelessWidget {
  final AppState state;
  final RadioController radio;
  const CommunityApp(this.state, this.radio, {super.key});
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xffd6af62),
      brightness: brightness,
      primary: const Color(0xffd6af62),
      onPrimary: const Color(0xff10213a),
      surface: dark ? const Color(0xff142337) : const Color(0xfffaf8f3),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xff0c1728)
          : const Color(0xfff1f2f4),
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xff0c1728)
            : const Color(0xfff1f2f4),
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark
            ? const Color(0xff162237)
            : const Color(0xffefe6d7),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      title: state.organisation.shortName,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: state.dark ? ThemeMode.dark : ThemeMode.light,
      home: AppShell(state, radio),
    ),
  );
}

class AppShell extends StatefulWidget {
  final AppState state;
  final RadioController radio;
  const AppShell(this.state, this.radio, {super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int tab = 0;
  Timer? timer;
  StreamSubscription<Uri?>? widgetLinks;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widgetLinks = PrayerWidgetService.links.listen(openWidgetLink);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      widget.state.notifications.onOpenInbox = () {
        if (!mounted) return;
        setState(() => tab = 3);
        showPrivatePage(context, widget.state, UpdatesPage(widget.state));
      };
      widget.state.notifications.onOpenPrayers = () {
        if (mounted) setState(() => tab = 0);
      };
      widget.state.notifications.dispatchPendingOpen();
      try {
        openWidgetLink(await PrayerWidgetService.initialLink());
      } catch (_) {
        // An unavailable extension does not stop the main app opening.
      }
    });
    startTimer();
  }

  void openWidgetLink(Uri? uri) {
    if (!mounted || uri?.scheme != 'community') return;
    if (uri!.host == 'tasbih') {
      showPage(context, TasbihPage(widget.state.preferences));
    } else if (uri.host == 'prayers') {
      setState(() => tab = 0);
    }
  }

  void startTimer() {
    timer?.cancel();
    timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => widget.state.refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      widget.radio.resume();
      widget.state.refresh();
      startTimer();
    } else {
      timer?.cancel();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widgetLinks?.cancel();
    widget.state.notifications.onOpenInbox = null;
    widget.state.notifications.onOpenPrayers = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          width: 150,
          height: 48,
          child: ContentImage(
            s.image(s.branding[s.dark ? 'headerDark' : 'headerLight']) ??
                'assets/brand/wordmark-${s.dark ? 'dark' : 'light'}.png',
            fit: BoxFit.contain,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Your account',
            onPressed: () => setState(() => tab = 3),
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: 'Radio',
            onPressed: () => showPage(context, RadioPage(widget.radio)),
            icon: const Icon(Icons.radio_outlined),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: switch (tab) {
          0 => HomeView(
            s,
            widget.radio,
            (value) => setState(() => tab = value),
          ),
          1 => ReadingView(s),
          2 => EducationView(s),
          _ => AccountView(s),
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showPage(context, TasbihPage(s.preferences)),
        icon: const Icon(Icons.touch_app_outlined),
        label: const Text('Tasbih'),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListenableBuilder(
            listenable: widget.radio,
            builder: (context, _) => widget.radio.playing
                ? ListTile(
                    dense: true,
                    leading: const Icon(Icons.radio),
                    title: const Text('Live radio'),
                    onTap: () => showPage(context, RadioPage(widget.radio)),
                    trailing: IconButton(
                      tooltip: 'Stop radio',
                      onPressed: widget.radio.stop,
                      icon: const Icon(Icons.stop),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() => tab = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                label: 'Reading',
              ),
              NavigationDestination(
                icon: Icon(Icons.school_outlined),
                label: 'Education',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Account',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
