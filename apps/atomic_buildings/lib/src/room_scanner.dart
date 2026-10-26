import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'roomplan.dart';

/// Scans a room with the device (Apple RoomPlan on a LiDAR iPhone or iPad).
abstract class RoomScanner {
  Future<bool> isSupported();

  /// Runs the scan UI; null when the person cancels.
  Future<ScannedRoom?> scan();
}

/// The native plugin (`ios/Runner/RoomScanPlugin.swift`); unsupported elsewhere.
class PlatformRoomScanner implements RoomScanner {
  static const _channel = MethodChannel('io.ontola.atomic_buildings/roomscan');

  @override
  Future<bool> isSupported() async {
    if (kIsWeb || !Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<ScannedRoom?> scan() async {
    final json = await _channel.invokeMethod<String>('scan');
    return json == null ? null : ScannedRoom.parse(json);
  }
}
