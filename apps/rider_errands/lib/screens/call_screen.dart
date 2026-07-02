import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// Free peer-to-peer voice call over WebRTC (flutter_webrtc). Signaling — the
/// offer/answer/ICE exchange — rides on Supabase Realtime (a broadcast channel
/// named by the trip), so there is NO paid calling vendor and no extra server.
/// STUN/TURN servers come from the backend (/api/calls/ice). The other party is
/// alerted by the existing FCM "ring" push and joins the same channel.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.tripId, required this.peerName, this.incoming = false});
  final String tripId;
  final String peerName;

  /// True when opened by answering an incoming-call push (so we don't ring back
  /// and we act as the callee, not the caller).
  final bool incoming;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String _status = 'Connecting…';
  bool _muted = false;
  bool _speaker = true;
  bool _permanentlyDenied = false;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RealtimeChannel? _channel;
  bool _remoteDescSet = false;
  final List<RTCIceCandidate> _pendingRemote = [];
  bool _closed = false;

  bool get _isCaller => !widget.incoming;

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

    // 1) Microphone permission.
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

    // 2) ICE servers (STUN + TURN) from the backend.
    List<Map<String, dynamic>> iceServers;
    try {
      final data = await api.get('/api/calls/ice') as Map<String, dynamic>;
      iceServers = ((data['iceServers'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      iceServers = [
        {'urls': ['stun:stun.l.google.com:19302']},
      ];
    }

    // 3) Peer connection + local mic.
    try {
      _pc = await createPeerConnection({
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',
      });
      _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
    } catch (e) {
      _set('Could not start the microphone: $e');
      return;
    }

    _pc!
      ..onIceCandidate = (c) {
        if (c.candidate != null) {
          _send('candidate', {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          });
        }
      }
      ..onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _set('In call');
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _set('Reconnecting…');
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _set('Call connection failed. Please use chat.');
        }
      }
      ..onTrack = (event) {
        // Remote audio plays automatically once the track arrives.
        if (event.track.kind == 'audio') _set('In call');
      };

    // 4) Signaling over Supabase Realtime (broadcast channel per trip).
    final supa = Supabase.instance.client;
    final channel = supa.channel('call:${widget.tripId}');
    _channel = channel;
    channel.onBroadcast(event: 'signal', callback: (payload) => _onSignal(payload));
    channel.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (_isCaller) {
          await _makeOffer();
          // Tell the other party to open the call.
          try {
            await api.post('/api/calls/ring', {'tripId': widget.tripId});
          } catch (_) {}
          _set('Calling… waiting for the other person');
        } else {
          // Callee: announce readiness so the caller (re)sends its offer.
          _send('ready', {});
          _set('Connecting the call…');
        }
      }
    });
  }

  Future<void> _makeOffer() async {
    if (_pc == null) return;
    final offer = await _pc!.createOffer({});
    await _pc!.setLocalDescription(offer);
    _send('offer', {'sdp': offer.sdp, 'type': offer.type});
  }

  void _send(String type, Map<String, dynamic> data) {
    _channel?.sendBroadcastMessage(event: 'signal', payload: {'type': type, ...data});
  }

  Future<void> _onSignal(Map<String, dynamic> payload) async {
    if (_closed || _pc == null) return;
    final type = payload['type'] as String?;
    switch (type) {
      case 'ready': // callee joined → (re)send our offer
        if (_isCaller) await _makeOffer();
        break;
      case 'offer':
        if (!_isCaller) {
          await _pc!.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, payload['type'] as String));
          _remoteDescSet = true;
          await _drainCandidates();
          final answer = await _pc!.createAnswer({});
          await _pc!.setLocalDescription(answer);
          _send('answer', {'sdp': answer.sdp, 'type': answer.type});
        }
        break;
      case 'answer':
        if (_isCaller && !_remoteDescSet) {
          await _pc!.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, payload['type'] as String));
          _remoteDescSet = true;
          await _drainCandidates();
        }
        break;
      case 'candidate':
        final cand = RTCIceCandidate(
          payload['candidate'] as String?,
          payload['sdpMid'] as String?,
          (payload['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteDescSet) {
          await _pc!.addCandidate(cand);
        } else {
          _pendingRemote.add(cand); // buffer until the remote description is set
        }
        break;
      case 'bye':
        _set('Call ended.');
        if (mounted) Navigator.of(context).maybePop();
        break;
    }
  }

  Future<void> _drainCandidates() async {
    for (final c in _pendingRemote) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _pendingRemote.clear();
  }

  Future<void> _cleanup() async {
    _closed = true;
    try {
      _send('bye', {});
    } catch (_) {}
    try {
      await _channel?.unsubscribe();
    } catch (_) {}
    try {
      for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _localStream?.dispose();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    final tracks = _localStream?.getAudioTracks() ?? [];
    if (tracks.isEmpty) return;
    setState(() => _muted = !_muted);
    tracks.first.enabled = !_muted;
  }

  Future<void> _toggleSpeaker() async {
    if (_localStream == null) return;
    setState(() => _speaker = !_speaker);
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
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
