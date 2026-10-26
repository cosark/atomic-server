import 'dart:convert';
import 'dart:typed_data';

import 'package:atomic_chat/atomic_chat.dart' show HostedAi;
import 'package:atomic_flutter/atomic_flutter.dart' show AtomicAccountClient;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// The portal agents sign in to (the same as the atomic.place app's).
const defaultPortal = 'https://atomic.place';

Uint8List _decode(String input) {
  final standard = input.replaceAll('-', '+').replaceAll('_', '/');
  final rest = standard.length % 4;
  return base64Decode(rest == 0 ? standard : standard + '=' * (4 - rest));
}

/// The signing key and subject in an agent secret (the one-string, base64
/// JSON secret of [Identity.secret]).
class AgentKey {
  const AgentKey(this.subject, this.seed);

  factory AgentKey.fromSecret(String secret) {
    final json = jsonDecode(utf8.decode(_decode(secret))) as Map;
    return AgentKey(
        json['subject'] as String, _decode(json['privateKey'] as String));
  }

  final String subject;
  final Uint8List seed;

  /// The signature of [message], base64url without padding as Atomic writes it.
  String sign(String message) {
    final key = ed.newKeyFromSeed(seed);
    final signature =
        ed.sign(key, Uint8List.fromList(utf8.encode(message))).sublist(0, 64);
    return base64Url.encode(signature).replaceAll('=', '');
  }
}

/// The hosted AI of the atomic.place account whose identity is this device's
/// agent: the smallest version of what the atomic.place app does. It signs the
/// account in with the agent key (no saved session: it signs in again after a
/// restart) and asks the portal for the AI. An agent that is not an account
/// identity, or an unreachable portal, gives no AI. Accounts linked with a
/// link code on another device are not supported here.
class AgentAccount {
  AgentAccount(this.secret,
      {this.portal = defaultPortal,
      AtomicAccountClient Function(String portal)? client})
      : _client = client ?? AtomicAccountClient.new;

  /// The agent secret now, or null when signed out.
  final String? Function() secret;
  final String portal;
  final AtomicAccountClient Function(String portal) _client;

  String? _session;

  /// The account's AI; null when there is no account for this agent. Throws
  /// when the portal cannot be reached.
  Future<HostedAi?> hostedAi() async {
    final secret = this.secret();
    if (secret == null) return null;
    final key = AgentKey.fromSecret(secret);
    final client = _client(portal);
    if (_session != null) {
      client.restoreSession(_session!);
    } else if (await client.signInWithAgent(
        key.subject, (message) async => key.sign(message))) {
      _session = client.exportSession();
    } else {
      client.close();
      return null;
    }
    final status = await client.aiStatus();
    if (status == null) {
      client.close();
      return null;
    }
    return HostedAi(
      status: status,
      completions: (messages, model, tools) =>
          client.chatCompletionChunks(messages, model: model, tools: tools),
      enable: client.aiConsent,
      transcribe: (wav, {language}) =>
          client.transcribe(wav, language: language),
      voiceStatus: client.voiceStatus,
      // The building chat sends photos and falls back when the model refuses.
      acceptsImages: true,
      portal: client.origin,
    );
  }

  /// Mails [email] a link that makes the account with this agent as its
  /// identity. Throws a [StateError] with the portal's words when refused.
  Future<void> signUp(String email) async {
    final secret = this.secret();
    if (secret == null) throw StateError('This device has no identity yet');
    final key = AgentKey.fromSecret(secret);
    final client = _client(portal);
    try {
      await client.signUpWithAgent(
          email, key.subject, (message) async => key.sign(message));
    } finally {
      client.close();
    }
  }
}
