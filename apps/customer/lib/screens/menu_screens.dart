import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/trip_repository.dart';
import '../theme/app_theme.dart';
import 'paystack_webview.dart';

final _dateFmt = DateFormat('d MMM, h:mm a');

String _pretty(String s) => s.replaceAll('_', ' ');

// ---------------------------------------------------------------------------
// WALLET
// ---------------------------------------------------------------------------
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<TripRepository>().wallet();
  }

  void _reload() => setState(() => _future = context.read<TripRepository>().wallet());

  Future<void> _topUp() async {
    final repo = context.read<TripRepository>();
    final ctrl = TextEditingController(text: '500');
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Top up wallet'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (KES)', prefixText: 'KES '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)), child: const Text('Top up')),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;
    try {
      final checkout = await repo.initiateTopup(amount);
      if (!mounted) return;
      final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PaystackWebView(url: checkout.url, callbackUrl: TripRepository.paystackCallbackUrl),
      ));
      if (paid == true) {
        await repo.verifyPayment(checkout.reference);
        _reload();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _topUp,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Top up', style: TextStyle(color: Colors.white)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snap.hasError) return _ErrorView(message: '${snap.error}', onRetry: _reload);
          final wallet = (snap.data?['wallet'] as Map<String, dynamic>?) ?? {};
          final ledger = (snap.data?['ledger'] as List<dynamic>?) ?? [];
          final balance = (wallet['balance'] as num?)?.toInt() ?? 0;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryDark]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Wallet balance', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text('KES $balance', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
              const SizedBox(height: 8),
              if (ledger.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No transactions yet.', style: TextStyle(color: AppTheme.muted))))
              else
                ...ledger.map((e) {
                  final m = e as Map<String, dynamic>;
                  final credit = m['direction'] == 'credit';
                  final amt = (m['amount'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(credit ? Icons.south_west : Icons.north_east, color: credit ? AppTheme.accent : AppTheme.muted),
                    title: Text(m['reason'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(m['created_at'] != null ? _dateFmt.format(DateTime.parse(m['created_at'] as String).toLocal()) : ''),
                    trailing: Text('${credit ? '+' : '-'}KES $amt',
                        style: TextStyle(fontWeight: FontWeight.bold, color: credit ? AppTheme.accent : AppTheme.ink)),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TRIP HISTORY
// ---------------------------------------------------------------------------
class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});
  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<TripRepository>().myTrips();
  }

  void _reload() => setState(() => _future = context.read<TripRepository>().myTrips());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip History')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snap.hasError) return _ErrorView(message: '${snap.error}', onRetry: _reload);
          final trips = snap.data ?? [];
          if (trips.isEmpty) {
            return const Center(child: Text('No trips yet. Book your first ride!', style: TextStyle(color: AppTheme.muted)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: trips.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final t = trips[i];
              final fare = (t['final_fare'] as num?)?.toInt() ?? (t['base_fare'] as num?)?.toInt() ?? 0;
              final status = t['status'] as String? ?? '';
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_pretty(t['vehicle_class'] as String? ?? ''),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
                        Text('KES $fare', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(t['dropoff_address'] as String? ?? t['errand_type'] as String? ?? '—',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _StatusChip(status: status),
                        Text(t['created_at'] != null ? _dateFmt.format(DateTime.parse(t['created_at'] as String).toLocal()) : '',
                            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    Color c = AppTheme.muted;
    if (status == 'completed') c = AppTheme.accent;
    if (status == 'cancelled') c = Colors.red;
    if (status == 'in_progress' || status == 'searching') c = AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(_pretty(status), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

// ---------------------------------------------------------------------------
// SUPPORT
// ---------------------------------------------------------------------------
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const faqs = [
      ('How do I pay?', 'Once a rider is matched you pay 50% with Paystack to confirm, and the remaining 50% when you reach your destination.'),
      ('Can I cancel?', 'Yes — cancel before the rider starts the trip and your payment is refunded to your wallet right away.'),
      ('Why text-only chat?', 'For your safety, chat is text-only and auto-moderated. No phone numbers are shared.'),
      ('How are fares set?', 'Fares are calculated from distance, time and conditions. The price you pay is confirmed before you pay the first 50%.'),
      ('What are commuter plans?', 'For errands you do regularly, set up a commuter plan to repeat them automatically on a daily, weekday or weekly schedule.'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: const [
                Icon(Icons.support_agent, color: AppTheme.primary, size: 32),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('We’re here to help', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
                      SizedBox(height: 2),
                      Text('support@ubike.co.ke', style: TextStyle(color: AppTheme.primaryDark)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('Frequently asked', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
          const SizedBox(height: 6),
          ...faqs.map((f) => ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                children: [Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(f.$2, style: const TextStyle(color: AppTheme.muted)))],
              )),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppTheme.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
