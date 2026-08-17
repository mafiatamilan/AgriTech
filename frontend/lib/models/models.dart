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
            : IrrigationEvent.fromJson(json['last_watered'] as Map<String, dynamic>),
        nextWatering: json['next_watering'] == null
            ? null
            : IrrigationEvent.fromJson(json['next_watering'] as Map<String, dynamic>),
        currentStatus: json['current_status'] == null
            ? null
            : IrrigationEvent.fromJson(json['current_status'] as Map<String, dynamic>),
        moistureReadings: (json['moisture_readings'] as List? ?? [])
            .map((e) => MoistureReading.fromJson(e as Map<String, dynamic>))
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

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.imageUrl,
    this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
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