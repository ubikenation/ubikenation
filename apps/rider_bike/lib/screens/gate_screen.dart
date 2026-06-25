import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/rider_repository.dart';
import '../theme/app_theme.dart';
import 'account_status_screen.dart';
import 'home_screen.dart';
import 'registration_screen.dart';

/// Decides the rider's landing screen from their verification status.
class GateScreen extends StatefulWidget {
  const GateScreen({super.key});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  late Future<RiderRecord?> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<RiderRepository>().myStatus();
  }

  void _reload() => setState(() => _future = context.read<RiderRepository>().myStatus());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RiderRecord?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.primary)));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48, color: AppTheme.muted),
                    const SizedBox(height: 12),
                    Text('Could not reach the server.\n${snap.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _reload, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          );
        }

        final rider = snap.data;
        // No record, OR a record still in `submitted` (registration was started but the
        // documents/fee were not completed) → resume registration instead of jumping
        // to Account Status. The status only becomes `under_review` once everything is in.
        if (rider == null || rider.status == 'submitted') {
          return RegistrationScreen(onDone: _reload);
        }
        if (rider.status == 'activated') return const HomeScreen();
        return AccountStatusScreen(rider: rider, onRefresh: _reload);
      },
    );
  }
}
