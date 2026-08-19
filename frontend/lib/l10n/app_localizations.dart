import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'AgriTech'**
  String get appTitle;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get onboardingTitle;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us a bit about your farm'**
  String get onboardingSubtitle;

  /// No description provided for @onboardingPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get onboardingPhone;

  /// No description provided for @onboardingSoilType.
  ///
  /// In en, this message translates to:
  /// **'Soil type'**
  String get onboardingSoilType;

  /// No description provided for @soilSandy.
  ///
  /// In en, this message translates to:
  /// **'Sandy'**
  String get soilSandy;

  /// No description provided for @soilLoamy.
  ///
  /// In en, this message translates to:
  /// **'Loamy'**
  String get soilLoamy;

  /// No description provided for @soilClay.
  ///
  /// In en, this message translates to:
  /// **'Clay'**
  String get soilClay;

  /// No description provided for @soilSilty.
  ///
  /// In en, this message translates to:
  /// **'Silty'**
  String get soilSilty;

  /// No description provided for @soilPeaty.
  ///
  /// In en, this message translates to:
  /// **'Peaty'**
  String get soilPeaty;

  /// No description provided for @soilChalky.
  ///
  /// In en, this message translates to:
  /// **'Chalky'**
  String get soilChalky;

  /// No description provided for @onboardingLocality.
  ///
  /// In en, this message translates to:
  /// **'Area / locality'**
  String get onboardingLocality;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish setup'**
  String get onboardingFinish;

  /// No description provided for @onboardingPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a phone number'**
  String get onboardingPhoneInvalid;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navMotor.
  ///
  /// In en, this message translates to:
  /// **'Motor Control'**
  String get navMotor;

  /// No description provided for @navMarket.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get navMarket;

  /// No description provided for @navUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get navUpload;

  /// No description provided for @navRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Recommendations'**
  String get navRecommendations;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get navAccount;

  /// No description provided for @navNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get navNotifications;

  /// No description provided for @homeWaterSaved.
  ///
  /// In en, this message translates to:
  /// **'Water saved till date'**
  String get homeWaterSaved;

  /// No description provided for @homeLiters.
  ///
  /// In en, this message translates to:
  /// **'liters'**
  String get homeLiters;

  /// No description provided for @homeSignalStrength.
  ///
  /// In en, this message translates to:
  /// **'LoRa signal'**
  String get homeSignalStrength;

  /// No description provided for @homeNoSignal.
  ///
  /// In en, this message translates to:
  /// **'Device not connected'**
  String get homeNoSignal;

  /// No description provided for @homeMotorState.
  ///
  /// In en, this message translates to:
  /// **'Motor'**
  String get homeMotorState;

  /// No description provided for @homeNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get homeNotifications;

  /// No description provided for @homeViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get homeViewAll;

  /// No description provided for @homeNoNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get homeNoNotifications;

  /// No description provided for @homeWelcome.
  ///
  /// In en, this message translates to:
  /// **'Hi, {name}'**
  String homeWelcome(Object name);

  /// No description provided for @homeNoFarm.
  ///
  /// In en, this message translates to:
  /// **'No farm yet. Create one to get started.'**
  String get homeNoFarm;

  /// No description provided for @homeCreateFarm.
  ///
  /// In en, this message translates to:
  /// **'Create farm'**
  String get homeCreateFarm;

  /// No description provided for @motorLastWatered.
  ///
  /// In en, this message translates to:
  /// **'Last watered'**
  String get motorLastWatered;

  /// No description provided for @motorNextWatering.
  ///
  /// In en, this message translates to:
  /// **'Next watering'**
  String get motorNextWatering;

  /// No description provided for @motorNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get motorNever;

  /// No description provided for @motorConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm action'**
  String get motorConfirmTitle;

  /// No description provided for @motorConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to {action}?'**
  String motorConfirmAction(Object action);

  /// No description provided for @motorConfirmGo.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get motorConfirmGo;

  /// No description provided for @motorRunning.
  ///
  /// In en, this message translates to:
  /// **'Watering now'**
  String get motorRunning;

  /// No description provided for @motorIdle.
  ///
  /// In en, this message translates to:
  /// **'Not watering'**
  String get motorIdle;

  /// No description provided for @motorSoilMoisture.
  ///
  /// In en, this message translates to:
  /// **'Soil moisture'**
  String get motorSoilMoisture;

  /// No description provided for @motorMoistureUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Soil moisture data unavailable'**
  String get motorMoistureUnavailable;

  /// No description provided for @motorStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting irrigation…'**
  String get motorStarting;

  /// No description provided for @motorPairTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair a device'**
  String get motorPairTitle;

  /// No description provided for @motorPairUid.
  ///
  /// In en, this message translates to:
  /// **'Device UID'**
  String get motorPairUid;

  /// No description provided for @motorPairSecret.
  ///
  /// In en, this message translates to:
  /// **'Device secret'**
  String get motorPairSecret;

  /// No description provided for @motorPair.
  ///
  /// In en, this message translates to:
  /// **'Pair device'**
  String get motorPair;

  /// No description provided for @motorPaired.
  ///
  /// In en, this message translates to:
  /// **'Device paired'**
  String get motorPaired;

  /// No description provided for @motorStopCurrent.
  ///
  /// In en, this message translates to:
  /// **'Stop current watering'**
  String get motorStopCurrent;

  /// No description provided for @motorCancelNext.
  ///
  /// In en, this message translates to:
  /// **'Cancel next watering'**
  String get motorCancelNext;

  /// No description provided for @motorOn.
  ///
  /// In en, this message translates to:
  /// **'Motor ON'**
  String get motorOn;

  /// No description provided for @motorStaleData.
  ///
  /// In en, this message translates to:
  /// **'Showing last saved data · updated {time}'**
  String motorStaleData(Object time);

  /// No description provided for @marketTitle.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get marketTitle;

  /// No description provided for @marketNeedAddress.
  ///
  /// In en, this message translates to:
  /// **'Set your farm location so buyers can find you'**
  String get marketNeedAddress;

  /// No description provided for @marketSetAddress.
  ///
  /// In en, this message translates to:
  /// **'Set address'**
  String get marketSetAddress;

  /// No description provided for @marketCropName.
  ///
  /// In en, this message translates to:
  /// **'Crop name'**
  String get marketCropName;

  /// No description provided for @marketShelfLife.
  ///
  /// In en, this message translates to:
  /// **'Shelf life (days, optional)'**
  String get marketShelfLife;

  /// No description provided for @marketHarvestedDate.
  ///
  /// In en, this message translates to:
  /// **'Harvested date'**
  String get marketHarvestedDate;

  /// No description provided for @marketExpectedPrice.
  ///
  /// In en, this message translates to:
  /// **'Expected price (per kg)'**
  String get marketExpectedPrice;

  /// No description provided for @marketFindBuyers.
  ///
  /// In en, this message translates to:
  /// **'Find buyers'**
  String get marketFindBuyers;

  /// No description provided for @marketNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches yet — keeping your request open'**
  String get marketNoMatches;

  /// No description provided for @marketRequests.
  ///
  /// In en, this message translates to:
  /// **'Your requests'**
  String get marketRequests;

  /// No description provided for @marketExtendShelfLife.
  ///
  /// In en, this message translates to:
  /// **'Extend shelf life'**
  String get marketExtendShelfLife;

  /// No description provided for @marketAdditionalDays.
  ///
  /// In en, this message translates to:
  /// **'Additional days'**
  String get marketAdditionalDays;

  /// No description provided for @marketExtend.
  ///
  /// In en, this message translates to:
  /// **'Extend'**
  String get marketExtend;

  /// No description provided for @marketConfirmSale.
  ///
  /// In en, this message translates to:
  /// **'Confirm sale'**
  String get marketConfirmSale;

  /// No description provided for @marketConfirmSaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm sale?'**
  String get marketConfirmSaleTitle;

  /// No description provided for @marketConfirmSaleBody.
  ///
  /// In en, this message translates to:
  /// **'Mark this match as a confirmed sale? Other offers for this crop will be closed.'**
  String get marketConfirmSaleBody;

  /// No description provided for @marketSaleConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Sale confirmed'**
  String get marketSaleConfirmed;

  /// No description provided for @marketStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get marketStatusOpen;

  /// No description provided for @marketStatusMatched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get marketStatusMatched;

  /// No description provided for @marketDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days} days left'**
  String marketDaysLeft(Object days);

  /// No description provided for @marketSelectFarm.
  ///
  /// In en, this message translates to:
  /// **'Select a farm'**
  String get marketSelectFarm;

  /// No description provided for @marketShelfLifeCompatible.
  ///
  /// In en, this message translates to:
  /// **'Shelf-life compatible'**
  String get marketShelfLifeCompatible;

  /// No description provided for @marketShelfLifeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Shelf-life compatibility unknown'**
  String get marketShelfLifeUnknown;

  /// No description provided for @marketInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Crop name and harvested date are required'**
  String get marketInvalidInput;

  /// No description provided for @uploadPhotoAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Photo analysis'**
  String get uploadPhotoAnalysis;

  /// No description provided for @uploadChatAgent.
  ///
  /// In en, this message translates to:
  /// **'Chat agent'**
  String get uploadChatAgent;

  /// No description provided for @uploadPickImage.
  ///
  /// In en, this message translates to:
  /// **'Pick photo'**
  String get uploadPickImage;

  /// No description provided for @uploadAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get uploadAnalyze;

  /// No description provided for @uploadAnalysisStatus.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String uploadAnalysisStatus(Object status);

  /// No description provided for @uploadNoImage.
  ///
  /// In en, this message translates to:
  /// **'Pick a photo first'**
  String get uploadNoImage;

  /// No description provided for @uploadHealthStatus.
  ///
  /// In en, this message translates to:
  /// **'Health status'**
  String get uploadHealthStatus;

  /// No description provided for @uploadCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get uploadCrop;

  /// No description provided for @uploadDisease.
  ///
  /// In en, this message translates to:
  /// **'Disease'**
  String get uploadDisease;

  /// No description provided for @uploadConfidenceLevel.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get uploadConfidenceLevel;

  /// No description provided for @uploadSeverity.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get uploadSeverity;

  /// No description provided for @uploadRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Recommendation'**
  String get uploadRecommendation;

  /// No description provided for @uploadRemedies.
  ///
  /// In en, this message translates to:
  /// **'Remedies'**
  String get uploadRemedies;

  /// No description provided for @uploadPrevention.
  ///
  /// In en, this message translates to:
  /// **'Prevention'**
  String get uploadPrevention;

  /// No description provided for @uploadRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake photo'**
  String get uploadRetake;

  /// No description provided for @uploadRiskFactors.
  ///
  /// In en, this message translates to:
  /// **'Risk factors'**
  String get uploadRiskFactors;

  /// No description provided for @uploadDiseases.
  ///
  /// In en, this message translates to:
  /// **'Diseases detected'**
  String get uploadDiseases;

  /// No description provided for @uploadYieldEstimate.
  ///
  /// In en, this message translates to:
  /// **'Yield estimate'**
  String get uploadYieldEstimate;

  /// No description provided for @uploadAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask about your crop…'**
  String get uploadAsk;

  /// No description provided for @uploadSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get uploadSend;

  /// No description provided for @uploadLoading.
  ///
  /// In en, this message translates to:
  /// **'Analyzing…'**
  String get uploadLoading;

  /// No description provided for @recommendationsHealth.
  ///
  /// In en, this message translates to:
  /// **'Health analysis'**
  String get recommendationsHealth;

  /// No description provided for @recommendationsYield.
  ///
  /// In en, this message translates to:
  /// **'Yield analysis'**
  String get recommendationsYield;

  /// No description provided for @recommendationsNextSeason.
  ///
  /// In en, this message translates to:
  /// **'Next season recommendations'**
  String get recommendationsNextSeason;

  /// No description provided for @recommendationsNoData.
  ///
  /// In en, this message translates to:
  /// **'No data yet — upload a crop photo to get started'**
  String get recommendationsNoData;

  /// No description provided for @recommendationsConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence: {value}'**
  String recommendationsConfidence(Object value);

  /// No description provided for @recommendationsForecasts.
  ///
  /// In en, this message translates to:
  /// **'Yield forecasts'**
  String get recommendationsForecasts;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Preferred language'**
  String get settingsLanguage;

  /// No description provided for @settingsSoilType.
  ///
  /// In en, this message translates to:
  /// **'Soil type'**
  String get settingsSoilType;

  /// No description provided for @settingsLocality.
  ///
  /// In en, this message translates to:
  /// **'Area / locality'**
  String get settingsLocality;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsNotifWatering.
  ///
  /// In en, this message translates to:
  /// **'Watering alerts'**
  String get settingsNotifWatering;

  /// No description provided for @settingsNotifMatch.
  ///
  /// In en, this message translates to:
  /// **'Market matches'**
  String get settingsNotifMatch;

  /// No description provided for @settingsNotifSystem.
  ///
  /// In en, this message translates to:
  /// **'System alerts'**
  String get settingsNotifSystem;

  /// No description provided for @settingsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSave;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @accountTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountTitle;

  /// No description provided for @accountPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get accountPhone;

  /// No description provided for @accountSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get accountSave;

  /// No description provided for @accountSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get accountSaved;

  /// No description provided for @accountImpact.
  ///
  /// In en, this message translates to:
  /// **'Impact history'**
  String get accountImpact;

  /// No description provided for @accountNoImpact.
  ///
  /// In en, this message translates to:
  /// **'No impact recorded yet'**
  String get accountNoImpact;

  /// No description provided for @navImpact.
  ///
  /// In en, this message translates to:
  /// **'Tracks & Impact'**
  String get navImpact;

  /// No description provided for @impactPrecisionAgriculture.
  ///
  /// In en, this message translates to:
  /// **'Precision Agriculture'**
  String get impactPrecisionAgriculture;

  /// No description provided for @impactCircularSupplyChain.
  ///
  /// In en, this message translates to:
  /// **'Circular Supply Chain'**
  String get impactCircularSupplyChain;

  /// No description provided for @impactEmpty.
  ///
  /// In en, this message translates to:
  /// **'No impact data yet — run the farm agents to generate metrics'**
  String get impactEmpty;

  /// No description provided for @impactEstimated.
  ///
  /// In en, this message translates to:
  /// **'estimated'**
  String get impactEstimated;

  /// No description provided for @impactMeasured.
  ///
  /// In en, this message translates to:
  /// **'measured'**
  String get impactMeasured;

  /// No description provided for @impactBaseline.
  ///
  /// In en, this message translates to:
  /// **'baseline'**
  String get impactBaseline;

  /// No description provided for @impactOptimized.
  ///
  /// In en, this message translates to:
  /// **'optimized'**
  String get impactOptimized;

  /// No description provided for @impactSelectFarm.
  ///
  /// In en, this message translates to:
  /// **'Select a farm to view impact'**
  String get impactSelectFarm;

  /// No description provided for @vendorSignupTitle.
  ///
  /// In en, this message translates to:
  /// **'Vendor sign-up'**
  String get vendorSignupTitle;

  /// No description provided for @vendorSignup.
  ///
  /// In en, this message translates to:
  /// **'Create vendor account'**
  String get vendorSignup;

  /// No description provided for @vendorNeedTitle.
  ///
  /// In en, this message translates to:
  /// **'What I need'**
  String get vendorNeedTitle;

  /// No description provided for @vendorCropName.
  ///
  /// In en, this message translates to:
  /// **'Crop name'**
  String get vendorCropName;

  /// No description provided for @vendorQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity needed (kg)'**
  String get vendorQuantity;

  /// No description provided for @vendorExpectedPrice.
  ///
  /// In en, this message translates to:
  /// **'Expected price (per kg)'**
  String get vendorExpectedPrice;

  /// No description provided for @vendorAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get vendorAdd;

  /// No description provided for @vendorRequests.
  ///
  /// In en, this message translates to:
  /// **'My requests'**
  String get vendorRequests;

  /// No description provided for @vendorOpportunities.
  ///
  /// In en, this message translates to:
  /// **'Crops available from farmers'**
  String get vendorOpportunities;

  /// No description provided for @vendorAccept.
  ///
  /// In en, this message translates to:
  /// **'I\'ll buy this'**
  String get vendorAccept;

  /// No description provided for @vendorBidPlaced.
  ///
  /// In en, this message translates to:
  /// **'Interest sent to the farmer'**
  String get vendorBidPlaced;

  /// No description provided for @vendorEmpty.
  ///
  /// In en, this message translates to:
  /// **'No requests yet'**
  String get vendorEmpty;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonError;

  /// No description provided for @commonSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get commonSignOut;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @locationUseMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get locationUseMyLocation;

  /// No description provided for @locationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied — enter your location manually'**
  String get locationDenied;

  /// No description provided for @locationLatitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get locationLatitude;

  /// No description provided for @locationLongitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get locationLongitude;

  /// No description provided for @locationEnterManually.
  ///
  /// In en, this message translates to:
  /// **'Enter location manually'**
  String get locationEnterManually;

  /// No description provided for @locationSet.
  ///
  /// In en, this message translates to:
  /// **'Location set'**
  String get locationSet;

  /// No description provided for @locationInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid latitude and longitude'**
  String get locationInvalid;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @inventoryAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Inventory'**
  String get inventoryAddTitle;

  /// No description provided for @inventoryCropName.
  ///
  /// In en, this message translates to:
  /// **'Crop name'**
  String get inventoryCropName;

  /// No description provided for @inventoryQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity (kg)'**
  String get inventoryQuantity;

  /// No description provided for @inventoryQuantityInvalid.
  ///
  /// In en, this message translates to:
  /// **'Quantity must be greater than zero'**
  String get inventoryQuantityInvalid;

  /// No description provided for @inventoryHarvestDate.
  ///
  /// In en, this message translates to:
  /// **'Harvested date'**
  String get inventoryHarvestDate;

  /// No description provided for @inventoryStorageType.
  ///
  /// In en, this message translates to:
  /// **'Storage type'**
  String get inventoryStorageType;

  /// No description provided for @inventoryQualityGrade.
  ///
  /// In en, this message translates to:
  /// **'Quality grade'**
  String get inventoryQualityGrade;

  /// No description provided for @inventoryField.
  ///
  /// In en, this message translates to:
  /// **'Field (optional)'**
  String get inventoryField;

  /// No description provided for @inventoryGrade.
  ///
  /// In en, this message translates to:
  /// **'Grade {grade}'**
  String inventoryGrade(Object grade);

  /// No description provided for @storageAmbient.
  ///
  /// In en, this message translates to:
  /// **'Open Storage'**
  String get storageAmbient;

  /// No description provided for @storageShaded.
  ///
  /// In en, this message translates to:
  /// **'Shaded / Godown'**
  String get storageShaded;

  /// No description provided for @storageEvaporativeCooler.
  ///
  /// In en, this message translates to:
  /// **'Cold Storage'**
  String get storageEvaporativeCooler;

  /// No description provided for @storageRefrigerated.
  ///
  /// In en, this message translates to:
  /// **'Refrigerated Storage'**
  String get storageRefrigerated;

  /// No description provided for @inventoryAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add to inventory'**
  String get inventoryAddButton;

  /// No description provided for @inventoryList.
  ///
  /// In en, this message translates to:
  /// **'Your inventory'**
  String get inventoryList;

  /// No description provided for @inventoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No inventory yet — add your harvested crops above'**
  String get inventoryEmpty;

  /// No description provided for @inventoryAdded.
  ///
  /// In en, this message translates to:
  /// **'Inventory item added'**
  String get inventoryAdded;

  /// No description provided for @inventoryInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Enter crop name and quantity'**
  String get inventoryInvalidInput;

  /// No description provided for @inventoryNoFarm.
  ///
  /// In en, this message translates to:
  /// **'No farm found — create one first'**
  String get inventoryNoFarm;

  /// No description provided for @navPerformance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get navPerformance;

  /// No description provided for @performanceRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Record Crop Performance'**
  String get performanceRecordTitle;

  /// No description provided for @performanceCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop name'**
  String get performanceCrop;

  /// No description provided for @performanceSeason.
  ///
  /// In en, this message translates to:
  /// **'Season (e.g. 2026-Q2)'**
  String get performanceSeason;

  /// No description provided for @performancePlantedDate.
  ///
  /// In en, this message translates to:
  /// **'Planted date'**
  String get performancePlantedDate;

  /// No description provided for @performanceHarvestDate.
  ///
  /// In en, this message translates to:
  /// **'Harvest date'**
  String get performanceHarvestDate;

  /// No description provided for @performanceYield.
  ///
  /// In en, this message translates to:
  /// **'Yield (kg)'**
  String get performanceYield;

  /// No description provided for @performanceRevenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue (₹)'**
  String get performanceRevenue;

  /// No description provided for @performanceCost.
  ///
  /// In en, this message translates to:
  /// **'Cost (₹)'**
  String get performanceCost;

  /// No description provided for @performanceNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get performanceNotes;

  /// No description provided for @performanceRecordButton.
  ///
  /// In en, this message translates to:
  /// **'Record performance'**
  String get performanceRecordButton;

  /// No description provided for @performanceHistory.
  ///
  /// In en, this message translates to:
  /// **'Performance history'**
  String get performanceHistory;

  /// No description provided for @performanceEmpty.
  ///
  /// In en, this message translates to:
  /// **'No performance records yet'**
  String get performanceEmpty;

  /// No description provided for @performanceRecorded.
  ///
  /// In en, this message translates to:
  /// **'Performance recorded'**
  String get performanceRecorded;

  /// No description provided for @performanceInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Enter crop name and at least yield or revenue'**
  String get performanceInvalidInput;

  /// No description provided for @settingsIrrigationSetup.
  ///
  /// In en, this message translates to:
  /// **'Irrigation setup'**
  String get settingsIrrigationSetup;

  /// No description provided for @settingsIrrigationSetupHint.
  ///
  /// In en, this message translates to:
  /// **'These values are used by the irrigation agent to estimate how long to water. Complete them for accurate recommendations.'**
  String get settingsIrrigationSetupHint;

  /// No description provided for @settingsFieldArea.
  ///
  /// In en, this message translates to:
  /// **'Field area (m²)'**
  String get settingsFieldArea;

  /// No description provided for @settingsCropType.
  ///
  /// In en, this message translates to:
  /// **'Crop type'**
  String get settingsCropType;

  /// No description provided for @settingsCropOther.
  ///
  /// In en, this message translates to:
  /// **'Other / custom crop'**
  String get settingsCropOther;

  /// No description provided for @settingsPlantedDate.
  ///
  /// In en, this message translates to:
  /// **'Planted date'**
  String get settingsPlantedDate;

  /// No description provided for @settingsPumpFlow.
  ///
  /// In en, this message translates to:
  /// **'Pump flow rate (L/min)'**
  String get settingsPumpFlow;

  /// No description provided for @settingsFieldSaved.
  ///
  /// In en, this message translates to:
  /// **'Irrigation setup saved'**
  String get settingsFieldSaved;

  /// No description provided for @settingsFieldInvalidArea.
  ///
  /// In en, this message translates to:
  /// **'Field area must be greater than zero'**
  String get settingsFieldInvalidArea;

  /// No description provided for @settingsFieldInvalidPump.
  ///
  /// In en, this message translates to:
  /// **'Pump flow must be greater than zero'**
  String get settingsFieldInvalidPump;

  /// No description provided for @settingsNoFarm.
  ///
  /// In en, this message translates to:
  /// **'No farm found — create one first'**
  String get settingsNoFarm;

  /// No description provided for @cropTomato.
  ///
  /// In en, this message translates to:
  /// **'Tomato'**
  String get cropTomato;

  /// No description provided for @cropOkra.
  ///
  /// In en, this message translates to:
  /// **'Okra'**
  String get cropOkra;

  /// No description provided for @cropSpinach.
  ///
  /// In en, this message translates to:
  /// **'Spinach'**
  String get cropSpinach;

  /// No description provided for @cropOnion.
  ///
  /// In en, this message translates to:
  /// **'Onion'**
  String get cropOnion;

  /// No description provided for @cropPotato.
  ///
  /// In en, this message translates to:
  /// **'Potato'**
  String get cropPotato;

  /// No description provided for @cropMaize.
  ///
  /// In en, this message translates to:
  /// **'Maize'**
  String get cropMaize;

  /// No description provided for @homeWeatherTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Weather'**
  String get homeWeatherTitle;

  /// No description provided for @homeWeatherUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Weather unavailable right now'**
  String get homeWeatherUnavailable;

  /// No description provided for @homeWeatherMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get homeWeatherMax;

  /// No description provided for @homeWeatherConditionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get homeWeatherConditionUnknown;

  /// No description provided for @homeWeatherHumidity.
  ///
  /// In en, this message translates to:
  /// **'Humidity: {pct}%'**
  String homeWeatherHumidity(Object pct);

  /// No description provided for @homeWeatherRain.
  ///
  /// In en, this message translates to:
  /// **'Rain: {mm} mm'**
  String homeWeatherRain(Object mm);

  /// No description provided for @homeWeatherWind.
  ///
  /// In en, this message translates to:
  /// **'Wind: {kmh} km/h'**
  String homeWeatherWind(Object kmh);

  /// No description provided for @homeWeatherIntelligence.
  ///
  /// In en, this message translates to:
  /// **'Weather intelligence is being used for irrigation decisions'**
  String get homeWeatherIntelligence;

  /// No description provided for @homeWeatherRainExpected.
  ///
  /// In en, this message translates to:
  /// **'Rain expected — irrigation requirement reduced'**
  String get homeWeatherRainExpected;

  /// No description provided for @homeWeatherHotDry.
  ///
  /// In en, this message translates to:
  /// **'High temperature and low humidity — higher irrigation demand'**
  String get homeWeatherHotDry;

  /// No description provided for @homeIrrigationRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Recommended watering: {minutes} min · {liters} L · pump {flow} L/min'**
  String homeIrrigationRecommendation(
    Object flow,
    Object liters,
    Object minutes,
  );
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
