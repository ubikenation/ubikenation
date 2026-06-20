import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/trip_repository.dart';
import '../theme/app_theme.dart';

/// Text chat with the rider. Messages are auto-moderated server-side (phone
/// numbers, emails, off-platform arrangements etc. are blocked).
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.tripId});
  final String tripId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  List<Map<String, dynamic>> _messages = [];
  bool _sending = false;

  String get _me => Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final msgs = await context.read<TripRepository>().chatHistory(widget.tripId);
      if (mounted) setState(() => _messages = msgs);
    } catch (_) {/* keep polling */}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final repo = context.read<TripRepository>();
    try {
      final res = await repo.sendChat(widget.tripId, text);
      _ctrl.clear();
      await _load();
      if (mounted && res.blocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message blocked: ${res.reason ?? 'not allowed'}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat with rider')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final mine = m['sender_id'] == _me;
                final blocked = m['blocked'] == true;
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 280),
                    decoration: BoxDecoration(
                      color: blocked
                          ? Colors.red.shade50
                          : mine
                              ? AppTheme.primary
                              : AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      blocked ? 'Message blocked by moderation' : (m['body'] as String? ?? ''),
                      style: TextStyle(
                        color: blocked ? Colors.red : (mine ? Colors.white : AppTheme.ink),
                        fontStyle: blocked ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
