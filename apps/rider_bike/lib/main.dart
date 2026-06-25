import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'services/rider_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/connectivity_gate.dart';
import 'widgets/animated_splash.dart';
import 'screens/auth_screen.dart';
import 'screens/gate_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConfig.supabaseAnonKey,
  );

  final api = ApiClient();

  // Push notifications (best-effort; never block startup). Riders get "new request"
  // alerts; token is registered after sign-in.
  final push = PushService(api);
  try {
    await Firebase.initializeApp();
    await push.init();
    if (Supabase.instance.client.auth.currentSession != null) {
      await push.registerToken();
    }
    Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.session != null) push.registerToken();
    });
  } catch (_) {/* Firebase not configured — push disabled, app still runs */}

  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<ApiClient>.value(value: api),
        Provider<RiderRepository>(create: (_) => RiderRepository(api)),
      ],
      child: const RiderApp(),
    ),
  );
}

class RiderApp extends StatelessWidget {
  const RiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'U-Bike Rider',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AnimatedSplash(next: ConnectivityGate(child: _AuthGate())),
    );
  }
}

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
        return auth.isSignedIn ? const GateScreen() : const AuthScreen();
      },
    );
  }
}
