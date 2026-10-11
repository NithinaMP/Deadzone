import 'package:battery_plus/battery_plus.dart';

/// Mod #3: lets the mesh service check battery before agreeing to relay
/// OTHER people's traffic. Your own messages always still attempt to
/// send regardless of battery — this only throttles acting as a relay
/// for the rest of the mesh, which is the actual real-world constraint
/// worth modeling (a dying phone shouldn't be expected to keep carrying
/// everyone else's hops).
class BatteryService {
  final Battery _battery = Battery();
  static const int lowBatteryThreshold = 15; // percent

  Future<int> getBatteryLevel() => _battery.batteryLevel;

  Future<bool> isBatteryLow() async {
    final level = await getBatteryLevel();
    return level <= lowBatteryThreshold;
  }
}