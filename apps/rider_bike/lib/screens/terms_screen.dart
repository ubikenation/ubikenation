import 'package:flutter/material.dart';

import '../data/terms.dart';
import '../theme/app_theme.dart';

/// Shows the full Terms & Conditions and Privacy Policy (read-only) so users can
/// review them any time from the menu.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Text(
            kUBikeTerms,
            style: const TextStyle(fontSize: 13, height: 1.55, color: AppTheme.ink),
          ),
        ),
      ),
    );
  }
}
