enum PeerStatus { discovered, connecting, connected, lost }

/// A device we've either directly discovered nearby, or that we know about
/// because messages routed through it. `isDirect` distinguishes "in radio
/// range right now" from "exists somewhere in the mesh."
class PeerDevice {
  final String id; // nearby_connections endpointId (direct) or app-level id
  String displayName; // mutable: handshake may refine the name after discovery
  String? publicKeyB64; // learned on handshake, needed to encrypt to them
  PeerStatus status;
  bool isDirect;
  DateTime lastSeen;
  int rssiEstimate; // rough signal strength, -1 if unknown

  PeerDevice({
    required this.id,
    required this.displayName,
    this.publicKeyB64,
    this.status = PeerStatus.discovered,
    this.isDirect = true,
    DateTime? lastSeen,
    this.rssiEstimate = -1,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Rough 0-4 bar signal strength for the UI. nearby_connections doesn't
  /// expose real RSSI on all platforms, so this is deliberately simple —
  /// connected+direct peers show full bars, everything else degrades.
  int get signalBars {
    if (status == PeerStatus.connected && isDirect) return 4;
    if (status == PeerStatus.connecting) return 2;
    if (status == PeerStatus.discovered) return 1;
    return 0;
  }
}