import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Stores a salted hash of your PIN (never the PIN itself) on this phone
/// and checks it. After 5 wrong tries it makes you wait 30 seconds.
class PinService extends ChangeNotifier {
  static const int maxAttempts = 5;
  static const Duration lockoutTime = Duration(seconds: 30);

  late Box _box;

  Future<void> init() async {
    _box = await Hive.openBox('security');
  }

  bool get hasPin => _box.get('pinHash') != null;

  Future<String> _hash(String salt, String pin) async {
    final digest = await Sha256().hash(utf8.encode('$salt:$pin'));
    return base64Encode(digest.bytes);
  }

  String _newSalt() {
    final random = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  Future<void> setPin(String pin) async {
    final salt = _newSalt();
    await _box.put('pinSalt', salt);
    await _box.put('pinHash', await _hash(salt, pin));
    await _box.put('failedAttempts', 0);
    await _box.delete('lockedUntilMs');
    notifyListeners();
  }

  Future<void> clearPin() async {
    await _box.delete('pinSalt');
    await _box.delete('pinHash');
    await _box.delete('failedAttempts');
    await _box.delete('lockedUntilMs');
    notifyListeners();
  }

  /// How long you still have to wait after too many wrong tries,
  /// or null if you're free to try.
  Duration? get lockRemaining {
    final until = _box.get('lockedUntilMs') as int?;
    if (until == null) return null;
    final remaining = until - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : null;
  }

  Future<bool> verify(String pin) async {
    if (lockRemaining != null) return false;

    final salt = _box.get('pinSalt') as String?;
    final stored = _box.get('pinHash') as String?;
    if (salt == null || stored == null) return true; // no PIN set

    if (await _hash(salt, pin) == stored) {
      await _box.put('failedAttempts', 0);
      return true;
    }

    final fails = ((_box.get('failedAttempts') as int?) ?? 0) + 1;
    if (fails >= maxAttempts) {
      await _box.put('failedAttempts', 0);
      await _box.put(
        'lockedUntilMs',
        DateTime.now().add(lockoutTime).millisecondsSinceEpoch,
      );
    } else {
      await _box.put('failedAttempts', fails);
    }
    return false;
  }
}