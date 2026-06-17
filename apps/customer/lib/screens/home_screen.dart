import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'booking_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final name = auth.currentUser?.userMetadata?['full_name'] as String? ?? 'there';

    return Scaffold(
      appBar: AppBar(
        title: const Text('U-Bike'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Hi $name 👋',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.ink)),
            const Text('Where would you like to go?', style: TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.15,
              children: ServiceCategory.all.map((c) => _ServiceCard(category: c)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.category});
  final ServiceCategory category;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookingScreen(category: category)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(category.icon, size: 40, color: AppTheme.primary),
            const SizedBox(height: 10),
            Text(category.label,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
            const SizedBox(height: 4),
            Text('From KES ${category.minFare}', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
