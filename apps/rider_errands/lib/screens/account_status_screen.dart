import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Shows the verification pipeline (Submitted → Under Review → Approved → Activated),
/// matching the prototype's Rider Account Status panel.
class AccountStatusScreen extends StatelessWidget {
  const AccountStatusScreen({super.key, required this.rider, required this.onRefresh});
  final RiderRecord rider;
  final VoidCallback onRefresh;

  static const _stages = ['submitted', 'under_review', 'approved', 'activated'];
  static const _labels = {
    'submitted': 'Submitted',
    'under_review': 'Under Review',
    'approved': 'Approved',
    'activated': 'Activated',
  };

  @override
  Widget build(BuildContext context) {
    final currentIndex = _stages.indexOf(rider.status);
    final banned = rider.status == 'suspended' || rider.status == 'banned';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Status'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => context.read<AuthService>().signOut()),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your application',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.ink)),
              const SizedBox(height: 4),
              if (rider.isFounding)
                const Text('Founding Rider — free registration 🎉', style: TextStyle(color: AppTheme.green)),
              const SizedBox(height: 24),
              if (banned)
                _bannedCard(rider.status)
              else
                ...List.generate(_stages.length, (i) {
                  final done = i <= currentIndex;
                  final active = i == currentIndex;
                  return _stageRow(_labels[_stages[i]]!, done, active);
                }),
              const Spacer(),
              if (rider.status == 'approved')
                const Text('You are approved! Activation completes shortly — pull to refresh.',
                    style: TextStyle(color: AppTheme.muted)),
              if (rider.status == 'under_review')
                const Text('Documents received. Our team is reviewing your application.',
                    style: TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: onRefresh, child: const Text('Check Status')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stageRow(String label, bool done, bool active) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? AppTheme.green : AppTheme.muted, size: 28),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: done ? AppTheme.ink : AppTheme.muted,
              )),
        ],
      ),
    );
  }

  Widget _bannedCard(String status) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.block, color: AppTheme.red),
          const SizedBox(width: 12),
          Expanded(child: Text('Account $status. Contact support for details.')),
        ],
      ),
    );
  }
}
