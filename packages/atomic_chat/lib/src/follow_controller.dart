import 'package:flutter/foundation.dart';

/// Whom this device is following (the web's follow mode), if anyone. One per
/// app, kept by the [ShellController]: the page that is open follows the
/// leader's pages, and leaving by hand stops it.
class FollowController extends ChangeNotifier {
  String? _agent;

  /// The agent being followed; null when not following.
  String? get agent => _agent;

  bool isFollowing(String agent) => _agent == agent;

  void follow(String agent) {
    if (_agent == agent) return;
    _agent = agent;
    notifyListeners();
  }

  void stop() {
    if (_agent == null) return;
    _agent = null;
    notifyListeners();
  }
}
