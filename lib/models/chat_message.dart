import 'dart:convert';

/// A single message as it travels through the mesh. Relays only ever see
/// the ciphertext; only the intended recipient can read it.
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName; // shown in the Lobby so you know who said what
  final String receiverId; // a deviceId, or 'LOBBY' for everyone
  final String cipherTextB64;
  final String nonceB64;
  final String macB64;
  final String senderPublicKeyB64;
  final DateTime sentAt;
  int ttl;
  bool isBroadcast;
  String strategyTag;

  String? decryptedText;
  bool deliveredLocally = false;

  ChatMessage({
    required this.id,
    required this.senderId,
    this.senderName = '',
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
    'senderName': senderName,
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
    senderName: json['senderName'] ?? '',
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
    senderName: senderName,
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