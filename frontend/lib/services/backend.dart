import 'dart:io';

import '../core/api_client.dart';
import '../models/models.dart';

/// All FastAPI backend calls. Responses are JSON; shapes follow the
/// backend routers (see AGENTS.md §7 and PROMPT_BACKEND.md).
class Backend {
  Backend(this._api);

  final ApiClient _api;

  // ---- auth ----
  Future<OAuthExchange> exchangeOAuth(String accessToken) async {
    final json = await _api.post('/auth/oauth/exchange', body: {
      'access_token': accessToken,
    });
    return OAuthExchange.fromJson(json as Map<String, dynamic>);
  }

  // ---- farms ----
  Future<List<Farm>> getFarms() async {
    final json = await _api.get('/farms') as List;
    return json.map((e) => Farm.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Farm> createFarm(String name) async {
    final json = await _api.post('/farms', body: {'name': name});
    return Farm.fromJson(json as Map<String, dynamic>);
  }

  // ---- motor ----
  /// Raw JSON (also cached offline, so we keep the source map).
  Future<Map<String, dynamic>> getMotorStatusJson(String farmId) async {
    final json = await _api.get('/motor/status', query: {'farm_id': farmId});
    return json as Map<String, dynamic>;
  }

  Future<void> stopCurrent(String farmId) =>
      _api.post('/motor/stop-current', query: {'farm_id': farmId});

  Future<void> cancelNext(String farmId) =>
      _api.post('/motor/cancel-next', query: {'farm_id': farmId});

  Future<void> motorOn(String farmId) =>
      _api.post('/motor/on', query: {'farm_id': farmId});

  /// Pair an ESP32/LoRa device to a farm. Returns the paired device row
  /// (secret is stored hashed server-side; never echoed back).
  Future<PairedDevice> pairDevice(String farmId, String deviceUid, String deviceSecret) async {
    final json = await _api.post('/farms/$farmId/devices', body: {
      'device_uid': deviceUid,
      'device_secret': deviceSecret,
    });
    return PairedDevice.fromJson(json as Map<String, dynamic>);
  }

  // ---- market ----
  Future<List<Farm>> getAddressPrompt() async {
    final json = await _api.get('/market/address-prompt');
    return (json['farms'] as List)
        .map((e) => Farm.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateFarmLocation(String farmId, double lat, double lon) =>
      _api.patch('/farms/$farmId', body: {'latitude': lat, 'longitude': lon});

  Future<CropMatchResult> cropMatch({
    required String cropName,
    int? shelfLifeDays,
    required String harvestedDate,
    double? expectedPrice,
  }) async {
    final json = await _api.post('/market/crop-match', body: {
      'crop_name': cropName,
      'shelf_life_days': shelfLifeDays,
      'harvested_date': harvestedDate,
      'expected_price': expectedPrice,
    });
    return CropMatchResult.fromJson(json as Map<String, dynamic>);
  }

  Future<List<DemandRequest>> getDemandRequests() async {
    final json = await _api.get('/market/requests') as List;
    return json
        .map((e) => DemandRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> extendShelfLife(String requestId, int days) =>
      _api.patch('/market/$requestId/extend-shelf-life',
          body: {'additional_days': days});

  Future<void> confirmMatch(String matchId) =>
      _api.patch('/market/matches/$matchId/confirm');

  // ---- upload ----
  Future<CropImageUpload> uploadCropImage(
    String farmId,
    File file,
  ) async {
    final json = await _api.postMultipart(
      '/upload/crop-image',
      fields: {'farm_id': farmId},
      fileField: 'file',
      file: file,
    );
    return CropImageUpload.fromJson(json as Map<String, dynamic>);
  }

  Future<AnalysisStatus> getAnalysisStatus(String imageId) async {
    final json = await _api.get('/upload/$imageId/status');
    return AnalysisStatus.fromJson(json as Map<String, dynamic>);
  }

  // ---- chat ----
  Future<String> createChatSession(String? farmId) async {
    final json = await _api.post('/chat/sessions',
        body: {'farm_id': ?farmId});
    final id = (json as Map<String, dynamic>)['id'];
    return id as String;
  }

  Future<ChatMessage> sendChatMessage(
    String sessionId, {
    String? content,
    File? image,
  }) async {
    final json = image != null
        ? await _api.postMultipart(
            '/chat/sessions/$sessionId/messages',
            fields: {'content': ?content},
            fileField: 'image',
            file: image,
          )
        : await _api.post('/chat/sessions/$sessionId/messages',
            body: {'content': content});
    return ChatMessage.fromJson(json as Map<String, dynamic>);
  }

  // ---- recommendations ----
  Future<Map<String, dynamic>> getRecommendationsJson(String farmId) async {
    final json =
        await _api.get('/recommendations', query: {'farm_id': farmId});
    return json as Map<String, dynamic>;
  }

  // ---- settings ----
  Future<AppSettings> getSettings() async {
    final json = await _api.get('/settings');
    return AppSettings.fromJson(json as Map<String, dynamic>);
  }

  Future<void> updateSettings(AppSettings s) async {
    await _api.patch('/settings', body: {
      'preferred_language': s.preferredLanguage,
      'soil_type': s.soilType,
      'area_locality': s.areaLocality,
      'notification_watering': s.notificationWatering,
      'notification_match': s.notificationMatch,
      'notification_system': s.notificationSystem,
    });
  }

  // ---- account ----
  Future<AccountInfo> getAccount() async {
    final json = await _api.get('/account');
    return AccountInfo.fromJson(json as Map<String, dynamic>);
  }

  Future<void> updateAccount({String? phone, String? name}) =>
      _api.patch('/account',
          body: {'phone': ?phone, 'name': ?name});

  Future<WaterSaved> getWaterSaved() async {
    final json = await _api.get('/account/water-saved');
    return WaterSaved.fromJson(json as Map<String, dynamic>);
  }

  // ---- impact / tracks ----
  Future<ImpactMetrics> getImpact(String farmId) async {
    final json = await _api.get('/impact', query: {'farm_id': farmId});
    return ImpactMetrics.fromJson(json as Map<String, dynamic>);
  }

  // ---- notifications ----
  Future<List<AppNotification>> getNotifications() async {
    final json = await _api.get('/notifications') as List;
    return json
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markNotificationRead(String id) =>
      _api.patch('/notifications/$id/read');

  // ---- vendors ----
  Future<void> vendorSignup() => _api.post('/vendors/signup');

  Future<List<VendorRequest>> vendorGetRequests() async {
    final json = await _api.get('/vendors/requests') as List;
    return json
        .map((e) => VendorRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> vendorCreateRequest({
    required String cropName,
    double? quantityNeeded,
    double? expectedPrice,
  }) =>
      _api.post('/vendors/requests', body: {
        'crop_name': cropName,
        'quantity_needed': quantityNeeded,
        'expected_price': expectedPrice,
      });

  Future<List<DemandRequest>> vendorOpportunities() async {
    final json = await _api.get('/vendors/opportunities') as List;
    return json
        .map((e) => DemandRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> vendorAccept(String requestId) =>
      _api.post('/vendors/opportunities/$requestId/accept');
}

class OfflineResult<T> {
  OfflineResult(this.data, {required this.fromCache, this.savedAt});

  final T data;
  final bool fromCache;
  final DateTime? savedAt;
}