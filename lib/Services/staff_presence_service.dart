import 'package:flutter/foundation.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';

/// Centralised, self-contained "staff presence / token validation" feature.
///
/// This is the single place ("ref") that both login and logout call:
/// - On LOGIN it announces "Staff logged in" to the staff's other devices.
/// - On LOGOUT it tests the remaining tokens, prunes the invalid ones from the
///   staff record, and only flips `is_available` to false if NONE are reachable.
///
/// To completely remove/disable the feature, set [enabled] to false. When
/// disabled, [onLogout] returns false so the caller falls back to the old
/// behaviour (if tokens remain, `is_available` is left untouched), and [onLogin]
/// does nothing.
class StaffPresenceService {
  /// LOGIN: announce to the staff's other [tokens] that they logged in, using a
  /// time-of-day greeting (Good morning / afternoon / evening) as the title.
  /// Fire-and-forget – does not modify the staff record.
  static Future<void> onLogin({
    required dynamic staffIdentifier,
    required List<String> tokens,
  }) async {
    if (tokens.isEmpty) return;
    final title = StaffService.timeGreeting();
    debugPrint(
        '👋 Presence: announcing "$title" to ${tokens.length} other device(s)');
    for (final token in tokens) {
      if (token.trim().isEmpty) continue;
      await StaffService.sendPresencePush(token, title: title);
    }
  }

  /// LOGOUT: test the remaining [tokens], keep only the reachable ones and prune
  /// the invalid ones from the staff record. If none are reachable, also set
  /// `is_available` to false.
  ///
  /// Returns true when the feature handled the update; false when disabled so
  /// the caller can apply the old behaviour.
  static Future<bool> onLogout({
    required dynamic staffIdentifier,
    required List<String> tokens,
  }) async {
    final result = await StaffService.classifyTokens(tokens);
    if (result.invalid.isNotEmpty) {
      debugPrint(
          '🗑️ Presence: removing invalid FCM tokens: ${result.invalid}');
    }

    if (result.valid.isNotEmpty) {
      // At least one device alive – keep only valid tokens, is_available unchanged.
      debugPrint(
          '✅ Presence: valid devices remain – keeping is_available unchanged (${result.valid})');
      await StaffService.updateStaffFcmToken(staffIdentifier, result.valid);
    } else {
      // No device reachable – mark unavailable and drop all tokens.
      debugPrint(
          '📱 Presence: no valid device – setting is_available false + removing invalid tokens');
      await StaffService.updateStaffAvailabilityWithFcmToken(
          staffIdentifier, false, []);
    }
    return true;
  }
}
