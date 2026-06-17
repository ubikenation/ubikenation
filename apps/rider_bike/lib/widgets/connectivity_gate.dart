import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Blocks the app with a clear prompt when there is no internet. Per U-Bike
/// rules, data or Wi-Fi must be on to use the app.
class ConnectivityGate extends StatefulWidget {
  const ConnectivityGate({super.key, required this.child});
  final Widget child;

  @override
  State<ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<ConnectivityGate> {
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = true;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = _connectivity.onConnectivityChanged.listen(_update);
  }

  Future<void> _check() async {
    try {
      _update(await _connectivity.checkConnectivity());
    } catch (_) {
      // assume online if the check fails, so we never lock users out wrongly
      if (mounted) setState(() => _online = true);
    }
  }

  void _update(List<ConnectivityResult> result) {
    final online = result.any((r) => r != ConnectivityResult.none);
    if (mounted) setState(() => _online = online);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_online) return widget.child;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 72, color: Color(0xFF12A0D7)),
                const SizedBox(height: 20),
                const Text('No Internet Connection',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Please turn on mobile data or Wi-Fi to use U-Bike.',
                    textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B7785))),
                const SizedBox(height: 24),
                FilledButton(onPressed: _check, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
