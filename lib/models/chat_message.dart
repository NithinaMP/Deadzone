import 'dart:convert';

/// A single message as it travels through the mesh.
///
/// IMPORTANT: `cipherText` is what every relay device actually sees and
/// forwards. Only the device whose `receiverId` matches its own ID, and
/// which holds the matching private key, can turn `cipherText` back into
/// `plainText`. Relays never touch `plainText` — it doesn't exist on
/// their device at all.
class ChatMessage {
  final String id; // UUID, used for dedup across the mesh
  final String senderId;
  final String receiverId; // peer device id, or 'BROADCAST' for SOS mode
  final String cipherTextB64; // base64 ciphertext
  final String nonceB64; // base64 AES-GCM nonce, needed to decrypt
  final String macB64; // base64 AES-GCM MAC tag
  final String senderPublicKeyB64; // sender's X25519 public key (for ECDH)
  final DateTime sentAt;
  int ttl; // hop budget, decremented at every relay, dropped at 0
  bool isBroadcast;
  String strategyTag; // Phase 3: which routing strategy originated this,
  // carried through every hop so metrics attribute
  // delivery/overhead to the right strategy

  // Local-only fields (not transmitted, not part of what a relay reads)
  String? decryptedText; // filled in locally once decrypted by the recipient
  bool deliveredLocally = false;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.cipherTextB64,
    required this.nonceB64,
    required this.macB64,
    required this.senderPublicKeyB64,
    required this.sentAt,
    this.ttl = 8,
    this.isBroadcast = false,
    this.strategyTag = 'flood',
    this.decryptedText,
  });

  Map<String, dynamic> toWireJson() => {
    'id': id,
    'senderId': senderId,
    'receiverId': receiverId,
    'cipherText': cipherTextB64,
    'nonce': nonceB64,
    'mac': macB64,
    'senderPubKey': senderPublicKeyB64,
    'sentAt': sentAt.toIso8601String(),
    'ttl': ttl,
    'broadcast': isBroadcast,
    'strategyTag': strategyTag,
  };

  static ChatMessage fromWireJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'],
    senderId: json['senderId'],
    receiverId: json['receiverId'],
    cipherTextB64: json['cipherText'],
    nonceB64: json['nonce'],
    macB64: json['mac'],
    senderPublicKeyB64: json['senderPubKey'],
    sentAt: DateTime.parse(json['sentAt']),
    ttl: json['ttl'],
    isBroadcast: json['broadcast'] ?? false,
    strategyTag: json['strategyTag'] ?? 'flood',
  );

  String encodeForTransport() => jsonEncode(toWireJson());

  static ChatMessage decodeFromTransport(String raw) =>
      fromWireJson(jsonDecode(raw));

  ChatMessage copyWithTtl(int newTtl) => ChatMessage(
    id: id,
    senderId: senderId,
    receiverId: receiverId,
    cipherTextB64: cipherTextB64,
    nonceB64: nonceB64,
    macB64: macB64,
    senderPublicKeyB64: senderPublicKeyB64,
    sentAt: sentAt,
    ttl: newTtl,
    isBroadcast: isBroadcast,
    strategyTag: strategyTag,
    decryptedText: decryptedText,
  );
}