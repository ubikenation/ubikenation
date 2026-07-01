import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// Real-time voice call over ZEGOCLOUD. Both parties join the same room (the trip)
/// using a server-issued token; audio is published and any remote audio is played.
/// Audio-only — no video.
///
/// The flow is fully instrumented: every ZEGO failure (login/publish/engine) is
/// surfaced with its error code instead of hanging on "Calling…", so problems are
/// diagnosable on the spot.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.tripId, required this.peerName, this.incoming = false});
  final String tripId;
  final String peerName;

  /// True when this screen was opened by answering an incoming-call push (so we
  /// don't ring the caller back).
  final bool incoming;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String _status = 'Connecting…';
  bool _muted = false;
  bool _speaker = true;
  bool _inRoom = false;
  bool _engineCreated = false;
  bool _peerJoined = false;
  bool _permanentlyDenied = false;
  String? _roomId;
  String? _myStreamId;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _start() async {
    final api = context.read<ApiClient>();

    // 1) Microphone permission — a voice call is impossible without it.
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() {
        _permanentlyDenied = mic.isPermanentlyDenied;
        _status = mic.isPermanentlyDenied
            ? 'Microphone is blocked. Enable it in Settings to call.'
            : 'Microphone permission is needed to make a call.';
      });
      return;
    }

    // 2) Fetch a room token from our backend (verifies we're a party to the trip).
    Map<String, dynamic> data;
    int appId;
    String token;
    String userId;
    try {
      data = await api.get('/api/calls/token?tripId=${widget.tripId}') as Map<String, dynamic>;
      appId = (data['appId'] as num).toInt();
      token = data['token'] as String;
      userId = data['userId'] as String;
      _roomId = data['roomId'] as String;
      _myStreamId = '${_roomId}_$userId';
    } catch (e) {
      _set('Could not start the call (server): $e');
      return;
    }
    if (appId == 0 || token.isEmpty) {
      _set('Voice calling is not configured on the server.');
      return;
    }

    // 3) Create the engine. Destroy any leftover engine first so a re-open never
    //    hits "engine already created".
    try {
      try {
        await ZegoExpressEngine.destroyEngine();
      } catch (_) {/* nothing to destroy */}

      // Surface every SDK-level error while we're stabilising calls.
      ZegoExpressEngine.onDebugError = (code, func, info) {
        if (code != 0) debugPrint('[ZEGO] error $code in $func: $info');
      };
      ZegoExpressEngine.onApiCalledResult = (code, func, info) {
        if (code != 0) debugPrint('[ZEGO] api $func -> $code: $info');
      };

      await ZegoExpressEngine.createEngineWithProfile(
        ZegoEngineProfile(appId, ZegoScenario.StandardVoiceCall),
      );
      _engineCreated = true;
    } catch (e) {
      final missing = e.toString().contains('MissingPluginException');
      _set(missing
          ? 'Voice calling is unavailable right now. Please use chat instead.'
          : 'Could not start the audio engine: $e');
      return;
    }

    // 4) Register room / stream / publisher listeners BEFORE logging in.
    ZegoExpressEngine.onRoomStateChanged = (roomID, reason, errorCode, extended) {
      if (!mounted) return;
      if (reason == ZegoRoomStateChangedReason.Logined) {
        _set(_peerJoined ? 'In call' : 'Connected — waiting for the other person…');
      } else if (reason == ZegoRoomStateChangedReason.LoginFailed) {
        _set('Could not connect the call (code $errorCode). Please use chat.');
      } else if (reason == ZegoRoomStateChangedReason.Reconnecting) {
        _set('Reconnecting…');
      } else if (reason == ZegoRoomStateChangedReason.KickOut) {
        _set('Call ended (signed in elsewhere).');
      }
    };

    ZegoExpressEngine.onRoomStreamUpdate = (roomID, updateType, streamList, extended) {
      for (final s in streamList) {
        if (updateType == ZegoUpdateType.Add) {
          ZegoExpressEngine.instance.startPlayingStream(s.streamID);
          _peerJoined = true;
          _set('In call');
        } else {
          ZegoExpressEngine.instance.stopPlayingStream(s.streamID);
          _peerJoined = false;
          _set('The other person left the call.');
        }
      }
    };

    ZegoExpressEngine.onPublisherStateUpdate = (streamID, state, errorCode, extended) {
      if (!mounted) return;
      if (errorCode != 0) {
        _set('Could not send your audio (code $errorCode).');
      }
    };

    // 5) Log in to the room — CHECK the result. A bad token / wrong auth mode /
    //    network problem shows up here as a non-zero errorCode instead of a hang.
    try {
      final result = await ZegoExpressEngine.instance.loginRoom(
        _roomId!,
        ZegoUser(userId, userId),
        config: ZegoRoomConfig(0, true, token),
      );
      if (result.errorCode != 0) {
        _set('Could not connect the call (login ${result.errorCode}). Please use chat.');
        return;
      }
      _inRoom = true;
    } catch (e) {
      _set('Could not join the call: $e');
      return;
    }

    // Ring the other party so they get an "Incoming call" push and can join the
    // same room. Skipped when we're the one answering an incoming call.
    if (!widget.incoming) {
      try {
        await api.post('/api/calls/ring', {'tripId': widget.tripId});
      } catch (_) {/* best-effort — the call still works if they open it too */}
    }

    // 6) Publish our microphone and route audio to the speaker.
    try {
      await ZegoExpressEngine.instance.muteMicrophone(false);
      await ZegoExpressEngine.instance.startPublishingStream(_myStreamId!);
      await ZegoExpressEngine.instance.setAudioRouteToSpeaker(_speaker);
    } catch (e) {
      _set('Could not send your audio: $e');
      return;
    }

    if (!_peerJoined) _set('Calling… waiting for the other person to join');
  }

  Future<void> _cleanup() async {
    // Clear the global handlers first so their closures don't fire after dispose.
    ZegoExpressEngine.onRoomStateChanged = null;
    ZegoExpressEngine.onRoomStreamUpdate = null;
    ZegoExpressEngine.onPublisherStateUpdate = null;
    ZegoExpressEngine.onDebugError = null;
    ZegoExpressEngine.onApiCalledResult = null;
    try {
      if (_inRoom) {
        try {
          await ZegoExpressEngine.instance.stopPublishingStream();
        } catch (_) {}
        if (_roomId != null) {
          try {
            await ZegoExpressEngine.instance.logoutRoom(_roomId!);
          } catch (_) {}
        }
      }
      if (_engineCreated) await ZegoExpressEngine.destroyEngine();
    } catch (_) {/* ignore */}
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    if (!_inRoom) return;
    setState(() => _muted = !_muted);
    await ZegoExpressEngine.instance.muteMicrophone(_muted);
  }

  Future<void> _toggleSpeaker() async {
    if (!_engineCreated) return;
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ),
            if (_permanentlyDenied) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: openAppSettings, child: const Text('Open Settings')),
            ],
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
