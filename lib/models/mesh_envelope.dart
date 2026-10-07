import 'dart:convert';

/// Every payload that travels over the wire is wrapped in one of these so
/// a receiving device can tell "is this a handshake (exchange public
/// keys), an actual chat message, or a delivery ack?" before trying to
/// parse it as any of them.
class MeshEnvelope {
  static const String typeHandshake = 'handshake';
  static const String typeChat = 'chat';
  static const String typeAck = 'ack'; // Phase 3: delivery confirmation

  final String type;
  final Map<String, dynamic> data;

  MeshEnvelope({required this.type, required this.data});

  String encode() => jsonEncode({'type': type, 'data': data});

  static MeshEnvelope decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return MeshEnvelope(
      type: json['type'] as String,
      data: (json['data'] as Map).cast<String, dynamic>(),
    );
  }
}