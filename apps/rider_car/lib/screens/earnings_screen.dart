import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/rider_repository.dart';
import '../theme/app_theme.dart';

/// Rider wallet: available balance + pending earnings (80% of completed trips).
/// Payouts settle to the verified M-Pesa number in 24–48h.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  late Future<Earnings> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<RiderRepository>().earnings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: SafeArea(
        child: FutureBuilder<Earnings>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
            }
            final e = snap.data ?? const Earnings(balance: 0, pending: 0);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _card('Available Balance', e.balance, AppTheme.green, Icons.account_balance_wallet),
                const SizedBox(height: 14),
                _card('Pending (settling)', e.pending, AppTheme.primary, Icons.schedule),
                const SizedBox(height: 24),
                const Text('How earnings work',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
                const SizedBox(height: 8),
                const _Bullet('You keep 80% of every completed trip (company takes 20%).'),
                const _Bullet('Payouts go to your verified M-Pesa number.'),
                const _Bullet('Settlement takes 24–48 hours after a trip completes.'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _card(String label, int amount, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 4),
              Text('KES $amount',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(color: AppTheme.muted)),
          Expanded(child: Text(text, style: const TextStyle(color: AppTheme.muted))),
        ],
      ),
    );
  }
}
