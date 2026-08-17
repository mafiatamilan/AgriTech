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
  String get homeNoSignal => 'No device reported yet';

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
}
