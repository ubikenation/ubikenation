import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', width: 220, fit: BoxFit.contain),
            const SizedBox(height: 8),
            const Text('Rider', style: TextStyle(color: AppTheme.green, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 28),
            const CircularProgressIndicator(color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}
