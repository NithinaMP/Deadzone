enum PeerStatus { discovered, connecting, connected, lost }

/// A phone we've found nearby.
/// `id` is a TEMPORARY connection id that only means something on this
/// phone for this session. `deviceId` is the other phone's permanent
/// Deadzone id, and that's what messages are addressed to.
class PeerDevice {
  final String id;
  String? deviceId;
  String displayName;
  String? publicKeyB64;
  PeerStatus status;
  bool isDirect;
  DateTime lastSeen;
  int rssiEstimate;

  PeerDevice({
    required this.id,
    this.deviceId,
    required this.displayName,
    this.publicKeyB64,
    this.status = PeerStatus.discovered,
    this.isDirect = true,
    DateTime? lastSeen,
    this.rssiEstimate = -1,
  }) : lastSeen = lastSeen ?? DateTime.now();

  int get signalBars {
    if (status == PeerStatus.connected && isDirect) return 4;
    if (status == PeerStatus.connecting) return 2;
    if (status == PeerStatus.discovered) return 1;
    return 0;
  }
}