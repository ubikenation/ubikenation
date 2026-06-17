import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/trip_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/connectivity_gate.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConfig.supabaseAnonKey,
  );

  final api = ApiClient();
  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<ApiClient>.value(value: api),
        Provider<TripRepository>(create: (_) => TripRepository(api)),
      ],
      child: const UBikeApp(),
    ),
  );
}

class UBikeApp extends StatelessWidget {
  const UBikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'U-Bike',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const ConnectivityGate(child: _AuthGate()),
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
