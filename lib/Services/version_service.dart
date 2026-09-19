import 'dart:convert';
import 'package:guestezee_staffs_app/Config/api_end_points.dart';
import 'package:guestezee_staffs_app/Config/primary_config.dart';
import 'package:http/http.dart' as http;

class VersionService {
  static Future<http.Response> getUpdatedVersion() async {
    return await http.post(
      (Uri.parse(
          '${PrimaryConfigData.domainName}:${ApiEndPoints.versionCheck}')),
      body: jsonEncode(<String, dynamic>{
        "domain_name": PrimaryConfigData.domainName,
        "user_id": 16,
        "payload": {},
        "extras": {"find": {}},
      }),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );
  }
}
