import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// Real-time voice call over ZEGOCLOUD. Both parties join the same room (the trip)
/// using a server-issued token; audio is published and any remote audio is played.
/// Audio-only — no video.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.tripId, required this.peerName});
  final String tripId;
  final String peerName;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String _status = 'Connecting…';
  bool _muted = false;
  bool _speaker = true;
  bool _inRoom = false;
  String? _roomId;
  String? _myStreamId;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final api = context.read<ApiClient>();
    // Microphone permission is required to talk.
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (mounted) setState(() => _status = 'Microphone permission denied');
      return;
    }

    try {
      final data = await api.get('/api/calls/token?tripId=${widget.tripId}') as Map<String, dynamic>;
      final appId = (data['appId'] as num).toInt();
      final token = data['token'] as String;
      final userId = data['userId'] as String;
      _roomId = data['roomId'] as String;
      _myStreamId = '${_roomId}_$userId';

      await ZegoExpressEngine.createEngineWithProfile(
        ZegoEngineProfile(appId, ZegoScenario.StandardVoiceCall),
      );

      // Play remote streams as they appear / stop when they go.
      ZegoExpressEngine.onRoomStreamUpdate = (roomID, updateType, streamList, extendedData) {
        for (final s in streamList) {
          if (updateType == ZegoUpdateType.Add) {
            ZegoExpressEngine.instance.startPlayingStream(s.streamID);
            if (mounted) setState(() => _status = 'In call');
          } else {
            ZegoExpressEngine.instance.stopPlayingStream(s.streamID);
            if (mounted) setState(() => _status = 'Waiting for the other person…');
          }
        }
      };

      await ZegoExpressEngine.instance.loginRoom(
        _roomId!,
        ZegoUser(userId, userId),
        config: ZegoRoomConfig(0, true, token),
      );
      await ZegoExpressEngine.instance.startPublishingStream(_myStreamId!);
      await ZegoExpressEngine.instance.setAudioRouteToSpeaker(_speaker);
      if (mounted) {
        setState(() {
          _inRoom = true;
          _status = 'Calling… waiting for the other person to join';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Call failed: $e');
    }
  }

  Future<void> _cleanup() async {
    try {
      if (_inRoom) {
        if (_myStreamId != null) {
          await ZegoExpressEngine.instance.stopPublishingStream();
        }
        if (_roomId != null) {
          await ZegoExpressEngine.instance.logoutRoom(_roomId!);
        }
      }
      await ZegoExpressEngine.destroyEngine();
    } catch (_) {/* ignore */}
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await ZegoExpressEngine.instance.muteMicrophone(_muted);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speaker = !_speaker);
    await ZegoExpressEngine.instance.setAudioRouteToSpeaker(_speaker);
  }

  void _hangUp() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            CircleAvatar(
              radius: 56,
              backgroundColor: Colors.white24,
              child: Text(
                widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 44, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.peerName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(color: Colors.white70)),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _roundBtn(_muted ? Icons.mic_off : Icons.mic, _muted ? 'Unmute' : 'Mute', _toggleMute, active: _muted),
                const SizedBox(width: 28),
                _roundBtn(Icons.call_end, 'End', _hangUp, bg: const Color(0xFFE2483D), big: true),
                const SizedBox(width: 28),
                _roundBtn(_speaker ? Icons.volume_up : Icons.hearing, 'Speaker', _toggleSpeaker, active: _speaker),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, String label, VoidCallback onTap, {Color? bg, bool active = false, bool big = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg ?? (active ? Colors.white : Colors.white24),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(big ? 20 : 16),
              child: Icon(icon, color: bg != null ? Colors.white : (active ? AppTheme.ink : Colors.white), size: big ? 32 : 26),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
