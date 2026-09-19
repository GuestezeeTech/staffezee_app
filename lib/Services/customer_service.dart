import 'dart:convert';

import 'package:guestezee_staffs_app/Config/api_end_points.dart';
import 'package:guestezee_staffs_app/Config/primary_config.dart';
import 'package:http/http.dart' as http;

class CustomerService {
  /// Fetch customer by member id (hotel / property details).
  static Future<http.Response> getCustomerByMemberId(String memberId) async {
    return await http.post(
      Uri.parse(
          "${PrimaryConfigData.domainName}:${ApiEndPoints.getAllCustomers}"),
      body: jsonEncode({
        "domain_name": PrimaryConfigData.domainName,
        "user_id": PrimaryConfigData.userId,
        "extras": {
          "find": {"customer_member_id": memberId}
        }
      }),
      headers: const {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }

  /// Hotel access from customer/getall:
  /// - No / empty `data` => blocked (same as hotel_enabled false)
  /// - Record present, `hotel_enabled` missing => allowed (true)
  /// - Explicit `hotel_enabled: false` => blocked
  static bool parseHotelEnabled(Map<String, dynamic> responseBody) {
    try {
      if (responseBody['success'] != 1) return false;
      final result = responseBody['result'];
      if (result is! Map) return false;
      final data = result['data'];
      // No customer row → treat like hotel disabled.
      if (data is! List || data.isEmpty) return false;

      final customer = data.first;
      if (customer is! Map) return false;
      return _parseEnabledFlag(Map<String, dynamic>.from(customer));
    } catch (_) {
      return false;
    }
  }

  /// True when customer getall returned a usable hotel that is enabled.
  static bool isHotelAccessibleFromResponse(Map<String, dynamic> responseBody) {
    return parseHotelEnabled(responseBody);
  }

  static bool _parseEnabledFlag(Map<String, dynamic> source) {
    if (!source.containsKey('hotel_enabled')) return true;
    final value = source['hotel_enabled'];
    if (value == null) return true;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text == 'false' || text == '0' || text == 'no') return false;
    return true;
  }

  /// Expand `settings.room_range` into room numbers for task find filters.
  /// Each range uses [startRoom]..[endRoom] (inclusive) when both are ints.
  static List<String> parseRoomNumbers(Map<String, dynamic> responseBody) {
    final Set<String> rooms = {};
    try {
      if (responseBody['success'] != 1) return [];
      final result = responseBody['result'];
      if (result is! Map) return [];
      final data = result['data'];
      if (data is! List || data.isEmpty) return [];

      final customer = data.first;
      if (customer is! Map) return [];
      final customerMap = Map<String, dynamic>.from(customer);

      Map? settings;
      if (customerMap['settings'] is Map) {
        settings = customerMap['settings'] as Map;
      } else if (customerMap['property_details'] is Map) {
        final property = customerMap['property_details'] as Map;
        if (property['settings'] is Map) {
          settings = property['settings'] as Map;
        }
      }
      if (settings == null) return [];

      final roomRange = settings['room_range'] ?? settings['roomRange'];
      if (roomRange is! List) return [];

      for (final range in roomRange) {
        if (range is! Map) continue;
        final startRaw = (range['startRoom'] ??
                range['start_room'] ??
                range['start'] ??
                '')
            .toString()
            .trim();
        final endRaw =
            (range['endRoom'] ?? range['end_room'] ?? range['end'] ?? '')
                .toString()
                .trim();
        if (startRaw.isEmpty && endRaw.isEmpty) continue;

        final start = int.tryParse(startRaw);
        final end = int.tryParse(endRaw);
        if (start != null && end != null) {
          final low = start <= end ? start : end;
          final high = start <= end ? end : start;
          for (var i = low; i <= high; i++) {
            rooms.add(i.toString());
          }
        } else {
          if (startRaw.isNotEmpty) rooms.add(startRaw);
          if (endRaw.isNotEmpty && endRaw != startRaw) rooms.add(endRaw);
        }
      }
    } catch (_) {
      return rooms.toList();
    }
    return rooms.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a);
        final bi = int.tryParse(b);
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.compareTo(b);
      });
  }

  /// Extract hotel name from customer/getall response.
  static String? parseHotelName(Map<String, dynamic> responseBody) {
    try {
      if (responseBody['success'] != 1) return null;
      final result = responseBody['result'];
      if (result is! Map) return null;
      final data = result['data'];
      if (data is! List || data.isEmpty) return null;

      final customer = data.first;
      if (customer is! Map) return null;
      final customerMap = Map<String, dynamic>.from(customer);

      final propertyDetails = customerMap['property_details'];
      if (propertyDetails is Map) {
        final contactDetails = propertyDetails['contact_details'];
        if (contactDetails is Map) {
          final hotelName = contactDetails['hotel_name']?.toString().trim();
          if (hotelName != null && hotelName.isNotEmpty) {
            return hotelName;
          }
        }
      }

      final name = customerMap['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;

      return null;
    } catch (_) {
      return null;
    }
  }
}
