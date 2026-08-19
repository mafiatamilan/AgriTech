import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tiny JSON cache for the two offline-first endpoints.
/// Keys are namespaced per farm so a switcher never mixes farms.
class CacheStore {
  static const _motorKey = 'motor_status';
  static const _recsKey = 'recommendations';
  static const _accountTypeKey = 'account_type';

  Future<void> putMotorStatus(String farmId, dynamic json) =>
      _put(_motorKey, farmId, json);

  Future<dynamic> getMotorStatus(String farmId) => _get(_motorKey, farmId);

  Future<void> putRecommendations(String farmId, dynamic json) =>
      _put(_recsKey, farmId, json);

  Future<dynamic> getRecommendations(String farmId) => _get(_recsKey, farmId);

  Future<void> putAccountType(String accountType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountTypeKey, accountType);
  }

  Future<String?> getAccountType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accountTypeKey);
  }

  Future<void> _put(String prefix, String farmId, dynamic json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$prefix:$farmId',
      jsonEncode({'saved_at': DateTime.now().toIso8601String(), 'data': json}),
    );
  }

  Future<({dynamic data, DateTime savedAt})?> _get(
    String prefix,
    String farmId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$prefix:$farmId');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final data = map['data'];
      final savedAt = DateTime.tryParse(map['saved_at'] as String? ?? '');
      if (savedAt == null) return null;
      return (data: data, savedAt: savedAt);
    } on Object {
      return null;
    }
  }
}
