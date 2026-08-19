import 'dart:convert';

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

double? _num(dynamic v) => v == null ? null : (v as num).toDouble();

class FarmerProfile {
  FarmerProfile({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.preferredLanguage = 'en',
    this.soilType,
    this.areaLocality,
  });

  factory FarmerProfile.fromJson(Map<String, dynamic> json) => FarmerProfile(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        preferredLanguage: json['preferred_language'] as String? ?? 'en',
        soilType: json['soil_type'] as String?,
        areaLocality: json['area_locality'] as String?,
      );

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String preferredLanguage;
  final String? soilType;
  final String? areaLocality;
}

class OAuthExchange {
  OAuthExchange({required this.profile, required this.isNewUser});

  factory OAuthExchange.fromJson(Map<String, dynamic> json) => OAuthExchange(
        profile: FarmerProfile.fromJson(json['profile'] as Map<String, dynamic>),
        isNewUser: json['is_new_user'] as bool? ?? false,
      );

  final FarmerProfile profile;
  final bool isNewUser;
}

class Farm {
  Farm({required this.id, required this.name, this.location});

  factory Farm.fromJson(Map<String, dynamic> json) => Farm(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Unnamed farm',
        location: json['location'] as String?,
      );

  final String id;
  final String name;
  final String? location;
}

class IrrigationEvent {
  IrrigationEvent({
    required this.status,
    this.scheduledTime,
    this.startedAt,
    this.stoppedAt,
    this.durationSeconds,
  });

  factory IrrigationEvent.fromJson(Map<String, dynamic> json) =>
      IrrigationEvent(
        status: json['status'] as String? ?? '',
        scheduledTime: _date(json['scheduled_time']),
        startedAt: _date(json['started_at']),
        stoppedAt: _date(json['stopped_at']),
        durationSeconds: json['duration_seconds'] as int?,
      );

  final String status;
  final DateTime? scheduledTime;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final int? durationSeconds;
}

class MoistureReading {
  MoistureReading({required this.moisturePct, this.recordedAt});

  factory MoistureReading.fromJson(Map<String, dynamic> json) =>
      MoistureReading(
        moisturePct: _num(json['moisture_pct']) ?? 0,
        recordedAt: _date(json['recorded_at']),
      );

  final double moisturePct;
  final DateTime? recordedAt;
}

class MotorStatus {
  MotorStatus({
    this.lastWatered,
    this.nextWatering,
    this.currentStatus,
    required this.moistureReadings,
    this.signalStrength,
    this.motorRelayState,
  });

  factory MotorStatus.fromJson(Map<String, dynamic> json) => MotorStatus(
        lastWatered: json['last_watered'] == null
            ? null
            : IrrigationEvent.fromJson(
                Map<String, dynamic>.from(json['last_watered'] as Map)),
        nextWatering: json['next_watering'] == null
            ? null
            : IrrigationEvent.fromJson(
                Map<String, dynamic>.from(json['next_watering'] as Map)),
        currentStatus: json['current_status'] == null
            ? null
            : IrrigationEvent.fromJson(
                Map<String, dynamic>.from(json['current_status'] as Map)),
        moistureReadings: (json['moisture_readings'] as List? ?? [])
            .map((e) =>
                MoistureReading.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        signalStrength: json['signal_strength'] as int?,
        motorRelayState: json['motor_relay_state'] as bool?,
      );

  final IrrigationEvent? lastWatered;
  final IrrigationEvent? nextWatering;
  final IrrigationEvent? currentStatus;
  final List<MoistureReading> moistureReadings;
  final int? signalStrength;
  final bool? motorRelayState;
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.readAt,
    this.createdAt,
    this.relatedId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        readAt: _date(json['read_at']),
        createdAt: _date(json['created_at']),
        relatedId: json['related_id'] as String?,
      );

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime? readAt;
  final DateTime? createdAt;
  final String? relatedId;

  bool get isRead => readAt != null;
}

class MarketMatch {
  MarketMatch({
    required this.buyerName,
    this.offeredPrice,
    this.distanceKm,
    this.shelfLifeCompatible,
    this.matchScore,
  });

  factory MarketMatch.fromJson(Map<String, dynamic> json) => MarketMatch(
        buyerName: json['buyer_name'] as String? ?? 'Unknown buyer',
        offeredPrice: _num(json['offered_price']),
        distanceKm: _num(json['distance_km']),
        shelfLifeCompatible: json['shelf_life_compatible'] as bool?,
        matchScore: _num(json['match_score']),
      );

  final String buyerName;
  final double? offeredPrice;
  final double? distanceKm;
  final bool? shelfLifeCompatible;
  final double? matchScore;
}

class CropMatchResult {
  CropMatchResult({
    required this.demandRequestId,
    required this.matches,
    required this.status,
  });

  factory CropMatchResult.fromJson(Map<String, dynamic> json) => CropMatchResult(
        demandRequestId: json['demand_request_id'] as String,
        matches: (json['matches'] as List? ?? [])
            .map((e) => MarketMatch.fromJson(e as Map<String, dynamic>))
            .toList(),
        status: json['status'] as String? ?? 'open',
      );

  final String demandRequestId;
  final List<MarketMatch> matches;
  final String status;
}

class DemandRequest {
  DemandRequest({
    required this.id,
    required this.cropName,
    this.shelfLifeDays,
    this.harvestedDate,
    this.expectedPrice,
    this.shelfLifeExpiry,
    this.status = 'open',
    this.createdAt,
    this.matches = const [],
  });

  factory DemandRequest.fromJson(Map<String, dynamic> json) => DemandRequest(
        id: json['id'] as String,
        cropName: json['crop_name'] as String? ?? '',
        shelfLifeDays: json['shelf_life_days'] as int?,
        harvestedDate: _date(json['harvested_date']),
        expectedPrice: _num(json['expected_price']),
        shelfLifeExpiry: _date(json['shelf_life_expiry']),
        status: json['status'] as String? ?? 'open',
        createdAt: _date(json['created_at']),
        matches: (json['matches'] as List? ?? [])
            .map((e) => RescueMatch.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String cropName;
  final int? shelfLifeDays;
  final DateTime? harvestedDate;
  final double? expectedPrice;
  final DateTime? shelfLifeExpiry;
  final String status;
  final DateTime? createdAt;
  final List<RescueMatch> matches;

  Map<String, dynamic> get matchesPayload => {
        'demand_request_id': id,
        'crop_name': cropName,
        'status': status,
      };
}

class RescueMatch {
  RescueMatch({
    required this.id,
    this.demandRequestId,
    this.status = 'open',
    this.confirmedAt,
    this.createdAt,
    this.buyerInfo,
  });

  factory RescueMatch.fromJson(Map<String, dynamic> json) => RescueMatch(
        id: json['id'] as String,
        demandRequestId: json['demand_request_id'] as String?,
        status: json['status'] as String? ?? 'open',
        confirmedAt: _date(json['confirmed_at']),
        createdAt: _date(json['created_at']),
        buyerInfo: json['matched_buyer_info'] == null
            ? null
            : MarketMatch.fromJson(
                json['matched_buyer_info'] is String
                    ? jsonDecode(json['matched_buyer_info'] as String)
                        as Map<String, dynamic>
                    : json['matched_buyer_info'] as Map<String, dynamic>,
              ),
      );

  final String id;
  final String? demandRequestId;
  final String status;
  final DateTime? confirmedAt;
  final DateTime? createdAt;
  final MarketMatch? buyerInfo;

  bool get isConfirmed => status == 'confirmed';
}

class CropImageUpload {
  CropImageUpload({
    required this.id,
    required this.imageUrl,
    required this.analysisStatus,
  });

  factory CropImageUpload.fromJson(Map<String, dynamic> json) =>
      CropImageUpload(
        id: json['id'] as String,
        imageUrl: json['image_url'] as String? ?? '',
        analysisStatus: json['analysis_status'] as String? ?? 'pending',
      );

  final String id;
  final String imageUrl;
  final String analysisStatus;
}

class PairedDevice {
  PairedDevice({required this.id, this.deviceUid});

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        id: json['id'] as String,
        deviceUid: json['device_uid'] as String?,
      );

  final String id;
  final String? deviceUid;
}

class AgentResult {
  AgentResult({required this.agentType, this.resultJson, this.createdAt});

  factory AgentResult.fromJson(Map<String, dynamic> json) => AgentResult(
        agentType: json['agent_type'] as String? ?? '',
        resultJson: json['result_json'],
        createdAt: _date(json['created_at']),
      );

  final String agentType;
  final dynamic resultJson;
  final DateTime? createdAt;
}

class AnalysisStatus {
  AnalysisStatus({
    required this.id,
    required this.analysisStatus,
    required this.results,
  });

  factory AnalysisStatus.fromJson(Map<String, dynamic> json) =>
      AnalysisStatus(
        id: json['id'] as String,
        analysisStatus: json['analysis_status'] as String? ?? 'pending',
        results: (json['results'] as List? ?? [])
            .map((e) => AgentResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String analysisStatus;
  final List<AgentResult> results;

  bool get isDone => analysisStatus == 'done';
  bool get isFailed => analysisStatus == 'failed';
}

/// Typed view over a health agent's `result_json` (backend contract, §3).
class HealthResult {
  HealthResult({
    this.healthStatus,
    this.crop,
    this.disease,
    this.diseasesDetected = const [],
    this.confidenceLevel,
    this.severity,
    this.recommendation,
    this.remedies = const [],
    this.prevention = const [],
    this.retakeImage = false,
  });

  factory HealthResult.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return HealthResult();
    List<String> strList(dynamic v) =>
        v is List ? v.whereType<String>().toList() : <String>[];
    return HealthResult(
      healthStatus: json['health_status']?.toString(),
      crop: json['crop']?.toString(),
      disease: json['disease']?.toString(),
      diseasesDetected: strList(json['diseases_detected']),
      confidenceLevel: json['confidence_level']?.toString(),
      severity: json['severity']?.toString(),
      recommendation: json['recommendation']?.toString(),
      remedies: strList(json['remedies']),
      prevention: strList(json['prevention']),
      retakeImage: json['retake_image'] as bool? ?? false,
    );
  }

  final String? healthStatus;
  final String? crop;
  final String? disease;
  final List<String> diseasesDetected;
  final String? confidenceLevel;
  final String? severity;
  final String? recommendation;
  final List<String> remedies;
  final List<String> prevention;
  final bool retakeImage;
}

/// Typed view over a yield agent's `result_json` (backend contract, §3).
class YieldResult {
  YieldResult({
    this.cropType,
    this.expectedYieldKg,
    this.confidenceLevel,
    this.riskFactors = const [],
  });

  factory YieldResult.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return YieldResult();
    return YieldResult(
      cropType: json['crop_type']?.toString(),
      expectedYieldKg: _num(json['expected_yield_kg']),
      confidenceLevel: json['confidence_level']?.toString(),
      riskFactors: json['risk_factors'] is List
          ? json['risk_factors'].whereType<String>().toList()
          : <String>[],
    );
  }

  final String? cropType;
  final double? expectedYieldKg;
  final String? confidenceLevel;
  final List<String> riskFactors;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.imageUrl,
    this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
        createdAt: _date(json['created_at']),
      );

  final String id;
  final String role;
  final String content;
  final String? imageUrl;
  final DateTime? createdAt;

  bool get isUser => role == 'user';
}

class Recommendations {
  Recommendations({
    this.healthAnalysis,
    this.yieldAnalysis,
    this.nextSeason,
    required this.yieldForecasts,
  });

  factory Recommendations.fromJson(Map<String, dynamic> json) =>
      Recommendations(
        healthAnalysis: json['health_analysis'] == null
            ? null
            : AgentResult.fromJson(json['health_analysis'] as Map<String, dynamic>),
        yieldAnalysis: json['yield_analysis'] == null
            ? null
            : AgentResult.fromJson(json['yield_analysis'] as Map<String, dynamic>),
        nextSeason: json['next_season_recommendations'] == null
            ? null
            : AgentResult.fromJson(
                json['next_season_recommendations'] as Map<String, dynamic>),
        yieldForecasts: (json['yield_forecasts'] as List? ?? [])
            .map((e) => YieldForecast.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final AgentResult? healthAnalysis;
  final AgentResult? yieldAnalysis;
  final AgentResult? nextSeason;
  final List<YieldForecast> yieldForecasts;
}

class YieldForecast {
  YieldForecast({this.expectedYieldKg, this.createdAt});

  factory YieldForecast.fromJson(Map<String, dynamic> json) => YieldForecast(
        expectedYieldKg: _num(json['expected_yield_kg']),
        createdAt: _date(json['created_at']),
      );

  final double? expectedYieldKg;
  final DateTime? createdAt;
}

class AppSettings {
  AppSettings({
    this.preferredLanguage = 'en',
    this.soilType,
    this.areaLocality,
    this.notificationWatering = true,
    this.notificationMatch = true,
    this.notificationSystem = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        preferredLanguage: json['preferred_language'] as String? ?? 'en',
        soilType: json['soil_type'] as String?,
        areaLocality: json['area_locality'] as String?,
        notificationWatering: json['notification_watering'] as bool? ?? true,
        notificationMatch: json['notification_match'] as bool? ?? true,
        notificationSystem: json['notification_system'] as bool? ?? true,
      );

  String preferredLanguage;
  String? soilType;
  String? areaLocality;
  bool notificationWatering;
  bool notificationMatch;
  bool notificationSystem;
}

class ImpactMetric {
  ImpactMetric({
    required this.metricType,
    this.metricValue,
    this.createdAt,
  });

  factory ImpactMetric.fromJson(Map<String, dynamic> json) => ImpactMetric(
        metricType: json['metric_type'] as String? ?? '',
        metricValue: json['metric_value'],
        createdAt: _date(json['created_at']),
      );

  final String metricType;
  final dynamic metricValue;
  final DateTime? createdAt;
}

class ImpactMetricDetails {
  ImpactMetricDetails({
    required this.metricType,
    this.value,
    this.unit,
    this.baselineValue,
    this.optimizedValue,
    this.source,
    this.measuredOrEstimated,
    this.metadata,
    this.createdAt,
  });

  factory ImpactMetricDetails.fromJson(Map<String, dynamic> json) =>
      ImpactMetricDetails(
        metricType: json['metric_type'] as String? ?? '',
        value: _num(json['value']),
        unit: json['unit'] as String?,
        baselineValue: _num(json['baseline_value']),
        optimizedValue: _num(json['optimized_value']),
        source: json['source'] as String?,
        measuredOrEstimated: json['measured_or_estimated'] as String?,
        metadata: json['metadata'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null,
        createdAt: _date(json['created_at']),
      );

  final String metricType;
  final double? value;
  final String? unit;
  final double? baselineValue;
  final double? optimizedValue;
  final String? source;
  final String? measuredOrEstimated;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;

  String get label => metricType.replaceAll('_', ' ');
}

class ImpactMetrics {
  ImpactMetrics({required this.precisionAgriculture, required this.circularSupplyChain});

  factory ImpactMetrics.fromJson(Map<String, dynamic> json) {
    final groups = json['groups'] is Map
        ? Map<String, dynamic>.from(json['groups'] as Map)
        : <String, dynamic>{};
    List<ImpactMetricDetails> parse(String key) =>
        (groups[key] as List? ?? [])
            .map((e) => ImpactMetricDetails.fromJson(e as Map<String, dynamic>))
            .toList();
    return ImpactMetrics(
      precisionAgriculture: parse('precision_agriculture'),
      circularSupplyChain: parse('circular_supply_chain'),
    );
  }

  final List<ImpactMetricDetails> precisionAgriculture;
  final List<ImpactMetricDetails> circularSupplyChain;

  bool get isEmpty =>
      precisionAgriculture.isEmpty && circularSupplyChain.isEmpty;
}

class AccountInfo {
  AccountInfo({required this.profile, required this.impactMetrics});

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
        profile: FarmerProfile.fromJson(json['profile'] as Map<String, dynamic>),
        impactMetrics: (json['impact_metrics'] as List? ?? [])
            .map((e) => ImpactMetric.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final FarmerProfile profile;
  final List<ImpactMetric> impactMetrics;
}

class WaterSaved {
  WaterSaved({required this.totalLiters});

  factory WaterSaved.fromJson(Map<String, dynamic> json) => WaterSaved(
        totalLiters: (_num(json['total_water_saved_liters']) ?? 0),
      );

  final double totalLiters;
}

class InventoryItem {
  InventoryItem({
    required this.id,
    required this.farmId,
    required this.cropName,
    required this.quantity,
    this.harvestedDate,
    this.storageType,
    this.qualityGrade,
    this.statusInfo,
    this.createdAt,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        id: json['id'] as String,
        farmId: json['farm_id'] as String,
        cropName: json['crop_name'] as String? ?? '',
        quantity: (_num(json['quantity']) ?? 0).toDouble(),
        harvestedDate: json['harvested_date'] as String?,
        storageType: json['storage_type'] as String?,
        qualityGrade: json['quality_grade'] as String?,
        statusInfo: json['status_info'] != null
            ? InventoryStatus.fromJson(json['status_info'] as Map<String, dynamic>)
            : null,
        createdAt: _date(json['created_at']),
      );

  final String id;
  final String farmId;
  final String cropName;
  final double quantity;
  final String? harvestedDate;
  final String? storageType;
  final String? qualityGrade;
  final InventoryStatus? statusInfo;
  final DateTime? createdAt;
}

class InventoryStatus {
  InventoryStatus({
    required this.id,
    required this.inventoryId,
    required this.status,
    this.expiryDate,
    this.remainingDays,
    this.freshnessScore,
    this.createdAt,
  });

  factory InventoryStatus.fromJson(Map<String, dynamic> json) => InventoryStatus(
        id: json['id'] as String,
        inventoryId: json['inventory_id'] as String,
        status: json['status'] as String? ?? 'fresh',
        expiryDate: json['expiry_date'] as String?,
        remainingDays: json['remaining_days'] as int?,
        freshnessScore: _num(json['freshness_score']),
        createdAt: _date(json['created_at']),
      );

  final String id;
  final String inventoryId;
  final String status;
  final String? expiryDate;
  final int? remainingDays;
  final num? freshnessScore;
  final DateTime? createdAt;
}

class CropPerformance {
  CropPerformance({
    required this.id,
    required this.farmId,
    required this.crop,
    this.fieldId,
    this.season,
    this.plantedDate,
    this.harvestDate,
    this.yieldKg,
    this.revenue,
    this.cost,
    this.profit,
    this.weatherSummary,
    this.notes,
    this.createdAt,
  });

  factory CropPerformance.fromJson(Map<String, dynamic> json) => CropPerformance(
        id: json['id'] as String,
        farmId: json['farm_id'] as String,
        crop: json['crop'] as String? ?? '',
        fieldId: json['field_id'] as String?,
        season: json['season'] as String?,
        plantedDate: json['planted_date'] as String?,
        harvestDate: json['harvest_date'] as String?,
        yieldKg: _num(json['yield_kg']),
        revenue: _num(json['revenue']),
        cost: _num(json['cost']),
        profit: _num(json['profit']),
        weatherSummary: json['weather_summary'] as Map<String, dynamic>?,
        notes: json['notes'] as String?,
        createdAt: _date(json['created_at']),
      );

  final String id;
  final String farmId;
  final String crop;
  final String? fieldId;
  final String? season;
  final String? plantedDate;
  final String? harvestDate;
  final num? yieldKg;
  final num? revenue;
  final num? cost;
  final num? profit;
  final Map<String, dynamic>? weatherSummary;
  final String? notes;
  final DateTime? createdAt;
}

class VendorRequest {
  VendorRequest({
    required this.id,
    required this.cropName,
    this.quantityNeeded,
    this.expectedPrice,
    this.status = 'open',
    this.createdAt,
  });

  factory VendorRequest.fromJson(Map<String, dynamic> json) => VendorRequest(
        id: json['id'] as String,
        cropName: json['crop_name'] as String? ?? '',
        quantityNeeded: _num(json['quantity_needed']),
        expectedPrice: _num(json['expected_price']),
        status: json['status'] as String? ?? 'open',
        createdAt: _date(json['created_at']),
      );

  final String id;
  final String cropName;
  final double? quantityNeeded;
  final double? expectedPrice;
  final String status;
  final DateTime? createdAt;
}