import 'dart:io';

import '../core/api_client.dart';
import '../models/models.dart';

/// All FastAPI backend calls. Responses are JSON; shapes follow the
/// backend routers (see AGENTS.md §7 and PROMPT_BACKEND.md).
class Backend {
  Backend(this._api);

  final ApiClient _api;

  // ---- auth ----
  Future<AuthResponse> login(String email, String password) async {
    final json = await _api.post('/auth/login', body: {
      'email': email,
      'password': password,
    });
    return AuthResponse.fromJson(json as Map<String, dynamic>);
  }

  Future<AuthResponse> signup(
      String email, String password, String name, {String? phone}) async {
    final json = await _api.post('/auth/signup', body: {
      'email': email,
      'password': password,
      'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
    return AuthResponse.fromJson(json as Map<String, dynamic>);
  }

  Future<FarmerProfile> getProfile() async {
    final json = await _api.get('/auth/me');
    return FarmerProfile.fromJson(json as Map<String, dynamic>);
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

  // ---- fields (irrigation configuration) ----
  Future<List<FieldArea>> getFields(String farmId) async {
    final json = await _api.get('/farms/$farmId/fields') as List;
    return json
        .map((e) => FieldArea.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FieldArea> createField(String farmId, FieldArea field) async {
    final json = await _api.post('/farms/$farmId/fields', body: field.toJson());
    return FieldArea.fromJson(json as Map<String, dynamic>);
  }

  Future<FieldArea> updateField(String farmId, String fieldId, FieldArea field) async {
    final json = await _api.patch('/farms/$farmId/fields/$fieldId',
        body: field.toJson());
    return FieldArea.fromJson(json as Map<String, dynamic>);
  }

  // ---- weather (Home dashboard) ----
  Future<WeatherInfo> getFarmWeather(String farmId) async {
    final json = await _api.get('/farms/$farmId/weather');
    return WeatherInfo.fromJson(json as Map<String, dynamic>);
  }

  Future<CropMatchResult> cropMatch({
    required String cropName,
    double? quantityKg,
    int? shelfLifeDays,
    required String harvestedDate,
    double? expectedPrice,
  }) async {
    final json = await _api.post('/market/crop-match', body: {
      'crop_name': cropName,
      if (quantityKg != null) 'quantity_kg': quantityKg,
      if (shelfLifeDays != null) 'shelf_life_days': shelfLifeDays,
      'harvested_date': harvestedDate,
      if (expectedPrice != null) 'expected_price': expectedPrice,
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
    File file, {
    String? cropHint,
  }) async {
    final json = await _api.postMultipart(
      '/upload/crop-image',
      fields: {
        'farm_id': farmId,
        if (cropHint != null) 'crop_hint': cropHint,
      },
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
        body: {'farm_id': farmId});
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
            fields: {'content': content ?? ''},
            fileField: 'image',
            file: image,
            longTimeout: true,
          )
        : await _api.postForm(
            '/chat/sessions/$sessionId/messages',
            fields: {'content': content ?? ''},
            longTimeout: true,
          );
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

  Future<void> updateAccount({String? phone, String? name}) => _api.patch(
        '/account',
        body: {
          if (phone != null) 'phone': phone,
          if (name != null) 'name': name,
        },
      );

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
        if (quantityNeeded != null) 'quantity_needed': quantityNeeded,
        if (expectedPrice != null) 'expected_price': expectedPrice,
      });

  Future<List<DemandRequest>> vendorOpportunities() async {
    final json = await _api.get('/vendors/opportunities') as List;
    return json
        .map((e) => DemandRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> vendorAccept(
      String requestId, double quantityKg) async {
    final json = await _api.post('/vendors/opportunities/$requestId/accept',
        body: {'quantity_kg': quantityKg});
    return Map<String, dynamic>.from(json as Map);
  }

  // ---- inventory ----
  Future<List<InventoryItem>> getInventory() async {
    final json = await _api.get('/inventory') as List;
    return json
        .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addInventory({
    required String farmId,
    required String cropName,
    required double quantity,
    String? harvestedDate,
    String? fieldId,
    String? storageType,
    String? qualityGrade,
  }) =>
      _api.post('/inventory', body: {
        'farm_id': farmId,
        'crop_name': cropName,
        'quantity': quantity,
        if (harvestedDate != null) 'harvested_date': harvestedDate,
        if (fieldId != null) 'field_id': fieldId,
        if (storageType != null) 'storage_type': storageType,
        if (qualityGrade != null) 'quality_grade': qualityGrade,
      });

  // ---- performance ----
  Future<void> recordCropPerformance({
    required String farmId,
    required String crop,
    String? fieldId,
    String? season,
    String? plantedDate,
    String? harvestDate,
    double? yieldKg,
    double? revenue,
    double? cost,
    double? profit,
    Map<String, dynamic>? weatherSummary,
    String? notes,
  }) =>
      _api.post('/performance/crop', body: {
        'farm_id': farmId,
        'crop': crop,
        if (fieldId != null) 'field_id': fieldId,
        if (season != null) 'season': season,
        if (plantedDate != null) 'planted_date': plantedDate,
        if (harvestDate != null) 'harvest_date': harvestDate,
        if (yieldKg != null) 'yield_kg': yieldKg,
        if (revenue != null) 'revenue': revenue,
        if (cost != null) 'cost': cost,
        if (profit != null) 'profit': profit,
        if (weatherSummary != null) 'weather_summary': weatherSummary,
        if (notes != null) 'notes': notes,
      });
}

class OfflineResult<T> {
  OfflineResult(this.data, {required this.fromCache, this.savedAt});

  final T data;
  final bool fromCache;
  final DateTime? savedAt;
}
