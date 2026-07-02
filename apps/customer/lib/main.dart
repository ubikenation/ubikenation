import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'services/session_guard.dart';
import 'services/trip_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/connectivity_gate.dart';
import 'widgets/animated_splash.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/trip_screen.dart';
import 'screens/call_screen.dart';

/// Global keys so push notifications can show an in-app banner and navigate.
final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Set at launch when the user is returning after being away a while — the app
/// shows a "welcome back" greeting once it's up.
bool pendingWelcome = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Keep users signed in across restarts, but force a fresh sign-in after 48h idle.
  pendingWelcome = await SessionGuard.evaluate();

  final api = ApiClient();
  final repo = TripRepository(api);

  // Render the UI immediately. Push/Firebase init runs AFTER, in the background, so
  // a slow or missing FCM/Google-Play setup can never block startup (no black screen).
  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<ApiClient>.value(value: api),
        Provider<TripRepository>.value(value: repo),
      ],
      child: const UBikeApp(),
    ),
  );

  _initPush(api, repo);
}

/// Best-effort push setup, kicked off after the first frame so it never blocks
/// the UI. Registers the device token, shows foreground banners, opens the trip on tap.
Future<void> _initPush(ApiClient api, TripRepository repo) async {
  final push = PushService(
    api,
    messengerKey: messengerKey,
    onOpen: (data) async {
      final tripId = data['tripId'];
      if (tripId is! String) return;
      // Answering an incoming call → jump straight into the call room.
      if (data['type'] == 'incoming_call') {
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => CallScreen(
            tripId: tripId,
            peerName: (data['callerName'] as String?) ?? 'Caller',
            incoming: true,
          ),
        ));
        return;
      }
      try {
        final trip = await repo.getTrip(tripId);
        navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => TripScreen(trip: trip)));
      } catch (_) {/* trip gone / not signed in */}
    },
  );
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    await push.init();
    if (Supabase.instance.client.auth.currentSession != null) {
      await push.registerToken();
    }
    Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.session != null) {
        push.registerToken();
        SessionGuard.markSeen(); // stamp last-seen on sign-in so re-login starts fresh
      }
    });
  } catch (_) {/* Firebase not configured / slow — push disabled, app still runs */}
}

class UBikeApp extends StatefulWidget {
  const UBikeApp({super.key});

  @override
  State<UBikeApp> createState() => _UBikeAppState();
}

class _UBikeAppState extends State<UBikeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Greet a returning user once the UI is up.
    if (pendingWelcome) {
      pendingWelcome = false;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (Supabase.instance.client.auth.currentSession != null) SessionGuard.showWelcome(messengerKey);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the background: re-apply the 48h rule + greet if away a while.
    if (state == AppLifecycleState.resumed) {
      SessionGuard.evaluate().then((welcome) {
        if (welcome && Supabase.instance.client.auth.currentSession != null) {
          SessionGuard.showWelcome(messengerKey);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'U-bike',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: AppTheme.light,
      home: const AnimatedSplash(next: ConnectivityGate(child: _AuthGate())),
    );
  }
}

/// Routes between auth and home based on Supabase session state.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<AuthState>(
      stream: auth.onAuthChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        return auth.isSignedIn ? const HomeScreen() : const AuthScreen();
      },
    );
  }
}
