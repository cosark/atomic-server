/// Starts WebRTC peer sync for the app's drives and ties it to the app's
/// life: rooms open when the app is in front and signed in, and close when it
/// goes to the background (the OS ends the sockets there anyway) or signs out.
///
/// The Rust half is `atomic_lib::sync::webrtc_link`; until the bridge binds it
/// ([PeerSyncHost.backend] is set, see `planning/flutter-webrtc-peer.md`) this
/// does nothing, and nothing is contacted.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'atomic_auth.dart';
import 'atomic_client.dart';
import 'server_info.dart';
import 'session.dart';
import 'webrtc/peer_link_backend.dart';
import 'webrtc/peer_sync_service.dart';

/// The `signalingUrl` property of a drive.
const driveSignalingUrlProperty =
    'https://atomicdata.dev/properties/signaling-url';

class PeerSyncHost {
  PeerSyncHost._();
  static final instance = PeerSyncHost._();

  /// Binds the Rust link. Set once at startup by the bridge adapter.
  PeerLinkBackend? backend;

  /// The portal serving `/webrtc-signal` for drives that name no service.
  String portalUrl = 'https://atomic.place';

  WebRtcPeerSyncService? _service;
  Timer? _rescan;

  /// Per drive and server, for the length of a run: does the Cloud Server
  /// hold this drive. Asking costs a request.
  final _cloud = <String, Future<bool>>{};

  bool get running => _service != null;

  /// The latest status of each drive's room, for a status line.
  Map<String, String> get statuses => _service?.statuses ?? const {};

  Future<void> start() async {
    final backend = this.backend;
    if (backend == null) return;
    final service = _service ??= WebRtcPeerSyncService(
      backend: backend,
      listDrives: AtomicClient.listDrives,
      driveSignalingUrl: _driveSignalingUrl,
      usesCloudServer: (drive) =>
          _cloud.putIfAbsent(drive, () => _onCloud(drive)),
      portalUrl: portalUrl,
      onStatus: (drive, status) => debugPrint('Peer sync $drive: $status'),
    );
    // Drives created or joined while the app runs.
    _rescan ??= Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(_service?.start());
    });
    await service.start();
  }

  Future<void> stop() async {
    _rescan?.cancel();
    _rescan = null;
    final service = _service;
    _service = null;
    _cloud.clear();
    await service?.stop();
  }

  Future<String?> _driveSignalingUrl(String drive) async {
    try {
      final value =
          await AtomicClient.getProperty(drive, driveSignalingUrlProperty);
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// Same rule as the web's `driveUsesCloudServer`: the drive is on a managed
  /// server the account is connected to. A drive that exists only on this
  /// device (a private drive) is not, and is exactly what peers are for.
  Future<bool> _onCloud(String drive) async {
    try {
      final server = await AtomicSession.activeServer();
      if (server == null || server.isEmpty) return false;
      if (!(await fetchServerInfo(server)).managed) return false;
      final session = await AtomicSession.load();
      if (session == null) return false;
      return await fetchDriveUsage(
              server, drive, AtomicAgent.fromSecret(session.secret)) !=
          null;
    } catch (_) {
      return false;
    }
  }
}
