// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AgriTech';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get onboardingTitle => 'Welcome';

  @override
  String get onboardingSubtitle => 'Tell us a bit about your farm';

  @override
  String get onboardingPhone => 'Phone number';

  @override
  String get onboardingSoilType => 'Soil type';

  @override
  String get soilSandy => 'Sandy';

  @override
  String get soilLoamy => 'Loamy';

  @override
  String get soilClay => 'Clay';

  @override
  String get soilSilty => 'Silty';

  @override
  String get soilPeaty => 'Peaty';

  @override
  String get soilChalky => 'Chalky';

  @override
  String get onboardingLocality => 'Area / locality';

  @override
  String get onboardingFinish => 'Finish setup';

  @override
  String get onboardingPhoneInvalid => 'Please enter a phone number';

  @override
  String get navHome => 'Home';

  @override
  String get navMotor => 'Motor Control';

  @override
  String get navMarket => 'Market';

  @override
  String get navUpload => 'Upload';

  @override
  String get navRecommendations => 'Recommendations';

  @override
  String get navSettings => 'Settings';

  @override
  String get navAccount => 'Account';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get homeWaterSaved => 'Water saved till date';

  @override
  String get homeLiters => 'liters';

  @override
  String get homeSignalStrength => 'LoRa signal';

  @override
  String get homeNoSignal => 'Device not connected';

  @override
  String get homeMotorState => 'Motor';

  @override
  String get homeNotifications => 'Notifications';

  @override
  String get homeViewAll => 'View all';

  @override
  String get homeNoNotifications => 'No notifications yet';

  @override
  String homeWelcome(Object name) {
    return 'Hi, $name';
  }

  @override
  String get homeNoFarm => 'No farm yet. Create one to get started.';

  @override
  String get homeCreateFarm => 'Create farm';

  @override
  String get motorLastWatered => 'Last watered';

  @override
  String get motorNextWatering => 'Next watering';

  @override
  String get motorNever => 'Never';

  @override
  String get motorConfirmTitle => 'Confirm action';

  @override
  String motorConfirmAction(Object action) {
    return 'Are you sure you want to $action?';
  }

  @override
  String get motorConfirmGo => 'Confirm';

  @override
  String get motorRunning => 'Watering now';

  @override
  String get motorIdle => 'Not watering';

  @override
  String get motorSoilMoisture => 'Soil moisture';

  @override
  String get motorMoistureUnavailable => 'Soil moisture data unavailable';

  @override
  String get motorStarting => 'Starting irrigation…';

  @override
  String get motorPairTitle => 'Pair a device';

  @override
  String get motorPairUid => 'Device UID';

  @override
  String get motorPairSecret => 'Device secret';

  @override
  String get motorPair => 'Pair device';

  @override
  String get motorPaired => 'Device paired';

  @override
  String get motorStopCurrent => 'Stop current watering';

  @override
  String get motorCancelNext => 'Cancel next watering';

  @override
  String get motorOn => 'Motor ON';

  @override
  String motorStaleData(Object time) {
    return 'Showing last saved data · updated $time';
  }

  @override
  String get marketTitle => 'Market';

  @override
  String get marketNeedAddress =>
      'Set your farm location so buyers can find you';

  @override
  String get marketSetAddress => 'Set address';

  @override
  String get marketCropName => 'Crop name';

  @override
  String get marketShelfLife => 'Shelf life (days, optional)';

  @override
  String get marketHarvestedDate => 'Harvested date';

  @override
  String get marketExpectedPrice => 'Expected price (per kg)';

  @override
  String get marketFindBuyers => 'Find buyers';

  @override
  String get marketNoMatches => 'No matches yet — keeping your request open';

  @override
  String get marketRequests => 'Your requests';

  @override
  String get marketExtendShelfLife => 'Extend shelf life';

  @override
  String get marketAdditionalDays => 'Additional days';

  @override
  String get marketExtend => 'Extend';

  @override
  String get marketConfirmSale => 'Confirm sale';

  @override
  String get marketConfirmSaleTitle => 'Confirm sale?';

  @override
  String get marketConfirmSaleBody =>
      'Mark this match as a confirmed sale? Other offers for this crop will be closed.';

  @override
  String get marketSaleConfirmed => 'Sale confirmed';

  @override
  String get marketStatusOpen => 'Open';

  @override
  String get marketStatusMatched => 'Matched';

  @override
  String marketDaysLeft(Object days) {
    return '$days days left';
  }

  @override
  String get marketSelectFarm => 'Select a farm';

  @override
  String get marketShelfLifeCompatible => 'Shelf-life compatible';

  @override
  String get marketShelfLifeUnknown => 'Shelf-life compatibility unknown';

  @override
  String get marketInvalidInput => 'Crop name and harvested date are required';

  @override
  String get uploadPhotoAnalysis => 'Photo analysis';

  @override
  String get uploadChatAgent => 'Chat agent';

  @override
  String get uploadPickImage => 'Pick photo';

  @override
  String get uploadAnalyze => 'Analyze';

  @override
  String uploadAnalysisStatus(Object status) {
    return 'Status: $status';
  }

  @override
  String get uploadNoImage => 'Pick a photo first';

  @override
  String get uploadHealthStatus => 'Health status';

  @override
  String get uploadCrop => 'Crop';

  @override
  String get uploadDisease => 'Disease';

  @override
  String get uploadConfidenceLevel => 'Confidence';

  @override
  String get uploadSeverity => 'Severity';

  @override
  String get uploadRecommendation => 'Recommendation';

  @override
  String get uploadRemedies => 'Remedies';

  @override
  String get uploadPrevention => 'Prevention';

  @override
  String get uploadRetake => 'Retake photo';

  @override
  String get uploadRiskFactors => 'Risk factors';

  @override
  String get uploadDiseases => 'Diseases detected';

  @override
  String get uploadYieldEstimate => 'Yield estimate';

  @override
  String get uploadAsk => 'Ask about your crop…';

  @override
  String get uploadSend => 'Send';

  @override
  String get uploadLoading => 'Analyzing…';

  @override
  String get recommendationsHealth => 'Health analysis';

  @override
  String get recommendationsYield => 'Yield analysis';

  @override
  String get recommendationsNextSeason => 'Next season recommendations';

  @override
  String get recommendationsNoData =>
      'No data yet — upload a crop photo to get started';

  @override
  String recommendationsConfidence(Object value) {
    return 'Confidence: $value';
  }

  @override
  String get recommendationsForecasts => 'Yield forecasts';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Preferred language';

  @override
  String get settingsSoilType => 'Soil type';

  @override
  String get settingsLocality => 'Area / locality';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotifWatering => 'Watering alerts';

  @override
  String get settingsNotifMatch => 'Market matches';

  @override
  String get settingsNotifSystem => 'System alerts';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get accountTitle => 'Account';

  @override
  String get accountPhone => 'Phone number';

  @override
  String get accountSave => 'Save';

  @override
  String get accountSaved => 'Saved';

  @override
  String get accountImpact => 'Impact history';

  @override
  String get accountNoImpact => 'No impact recorded yet';

  @override
  String get navImpact => 'Tracks & Impact';

  @override
  String get impactPrecisionAgriculture => 'Precision Agriculture';

  @override
  String get impactCircularSupplyChain => 'Circular Supply Chain';

  @override
  String get impactEmpty =>
      'No impact data yet — run the farm agents to generate metrics';

  @override
  String get impactEstimated => 'estimated';

  @override
  String get impactMeasured => 'measured';

  @override
  String get impactBaseline => 'baseline';

  @override
  String get impactOptimized => 'optimized';

  @override
  String get impactSelectFarm => 'Select a farm to view impact';

  @override
  String get vendorSignupTitle => 'Vendor sign-up';

  @override
  String get vendorSignup => 'Create vendor account';

  @override
  String get vendorNeedTitle => 'What I need';

  @override
  String get vendorCropName => 'Crop name';

  @override
  String get vendorQuantity => 'Quantity needed (kg)';

  @override
  String get vendorExpectedPrice => 'Expected price (per kg)';

  @override
  String get vendorAdd => 'Add';

  @override
  String get vendorRequests => 'My requests';

  @override
  String get vendorOpportunities => 'Crops available from farmers';

  @override
  String get vendorAccept => 'I\'ll buy this';

  @override
  String get vendorBidPlaced => 'Interest sent to the farmer';

  @override
  String get vendorEmpty => 'No requests yet';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonError => 'Something went wrong';

  @override
  String get commonSignOut => 'Sign out';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get locationUseMyLocation => 'Use my location';

  @override
  String get locationDenied =>
      'Location permission denied — enter your location manually';

  @override
  String get locationLatitude => 'Latitude';

  @override
  String get locationLongitude => 'Longitude';

  @override
  String get locationEnterManually => 'Enter location manually';

  @override
  String get locationSet => 'Location set';

  @override
  String get locationInvalid => 'Enter a valid latitude and longitude';

  @override
  String get navInventory => 'Inventory';

  @override
  String get inventoryAddTitle => 'Add Inventory';

  @override
  String get inventoryCropName => 'Crop name';

  @override
  String get inventoryQuantity => 'Quantity (kg)';

  @override
  String get inventoryQuantityInvalid => 'Quantity must be greater than zero';

  @override
  String get inventoryHarvestDate => 'Harvested date';

  @override
  String get inventoryStorageType => 'Storage type';

  @override
  String get inventoryQualityGrade => 'Quality grade';

  @override
  String get inventoryField => 'Field (optional)';

  @override
  String inventoryGrade(Object grade) {
    return 'Grade $grade';
  }

  @override
  String get storageAmbient => 'Open Storage';

  @override
  String get storageShaded => 'Shaded / Godown';

  @override
  String get storageEvaporativeCooler => 'Cold Storage';

  @override
  String get storageRefrigerated => 'Refrigerated Storage';

  @override
  String get inventoryAddButton => 'Add to inventory';

  @override
  String get inventoryList => 'Your inventory';

  @override
  String get inventoryEmpty =>
      'No inventory yet — add your harvested crops above';

  @override
  String get inventoryAdded => 'Inventory item added';

  @override
  String get inventoryInvalidInput => 'Enter crop name and quantity';

  @override
  String get inventoryNoFarm => 'No farm found — create one first';

  @override
  String get navPerformance => 'Performance';

  @override
  String get performanceRecordTitle => 'Record Crop Performance';

  @override
  String get performanceCrop => 'Crop name';

  @override
  String get performanceSeason => 'Season (e.g. 2026-Q2)';

  @override
  String get performancePlantedDate => 'Planted date';

  @override
  String get performanceHarvestDate => 'Harvest date';

  @override
  String get performanceYield => 'Yield (kg)';

  @override
  String get performanceRevenue => 'Revenue (₹)';

  @override
  String get performanceCost => 'Cost (₹)';

  @override
  String get performanceNotes => 'Notes (optional)';

  @override
  String get performanceRecordButton => 'Record performance';

  @override
  String get performanceHistory => 'Performance history';

  @override
  String get performanceEmpty => 'No performance records yet';

  @override
  String get performanceRecorded => 'Performance recorded';

  @override
  String get performanceInvalidInput =>
      'Enter crop name and at least yield or revenue';

  @override
  String get settingsIrrigationSetup => 'Irrigation setup';

  @override
  String get settingsIrrigationSetupHint =>
      'These values are used by the irrigation agent to estimate how long to water. Complete them for accurate recommendations.';

  @override
  String get settingsFieldArea => 'Field area (m²)';

  @override
  String get settingsCropType => 'Crop type';

  @override
  String get settingsCropOther => 'Other / custom crop';

  @override
  String get settingsPlantedDate => 'Planted date';

  @override
  String get settingsPumpFlow => 'Pump flow rate (L/min)';

  @override
  String get settingsFieldSaved => 'Irrigation setup saved';

  @override
  String get settingsFieldInvalidArea => 'Field area must be greater than zero';

  @override
  String get settingsFieldInvalidPump => 'Pump flow must be greater than zero';

  @override
  String get settingsNoFarm => 'No farm found — create one first';

  @override
  String get cropTomato => 'Tomato';

  @override
  String get cropOkra => 'Okra';

  @override
  String get cropSpinach => 'Spinach';

  @override
  String get cropOnion => 'Onion';

  @override
  String get cropPotato => 'Potato';

  @override
  String get cropMaize => 'Maize';

  @override
  String get homeWeatherTitle => 'Today\'s Weather';

  @override
  String get homeWeatherUnavailable => 'Weather unavailable right now';

  @override
  String get homeWeatherMax => 'Max';

  @override
  String get homeWeatherConditionUnknown => 'Unknown';

  @override
  String homeWeatherHumidity(Object pct) {
    return 'Humidity: $pct%';
  }

  @override
  String homeWeatherRain(Object mm) {
    return 'Rain: $mm mm';
  }

  @override
  String homeWeatherWind(Object kmh) {
    return 'Wind: $kmh km/h';
  }

  @override
  String get homeWeatherIntelligence =>
      'Weather intelligence is being used for irrigation decisions';

  @override
  String get homeWeatherRainExpected =>
      'Rain expected — irrigation requirement reduced';

  @override
  String get homeWeatherHotDry =>
      'High temperature and low humidity — higher irrigation demand';

  @override
  String homeIrrigationRecommendation(
    Object flow,
    Object liters,
    Object minutes,
  ) {
    return 'Recommended watering: $minutes min · $liters L · pump $flow L/min';
  }
}
