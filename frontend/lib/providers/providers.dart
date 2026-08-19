import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api_client.dart';
import '../core/supabase.dart';
import '../models/models.dart';
import '../services/backend.dart';
import '../services/cache.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final backendProvider = Provider<Backend>(
  (ref) => Backend(ref.watch(apiClientProvider)),
);

final cacheProvider = Provider<CacheStore>((ref) => CacheStore());

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

enum AuthStatus { loading, needsLogin, needsOnboarding, ready }

enum AccountType { farmer, vendor }

class AccountTypeController extends Notifier<AccountType> {
  @override
  AccountType build() => AccountType.farmer;

  void setType(AccountType type) => state = type;
}

final accountTypeProvider =
    NotifierProvider<AccountTypeController, AccountType>(
      AccountTypeController.new,
    );

class AuthState {
  const AuthState(this.status, {this.profile});

  final AuthStatus status;
  final FarmerProfile? profile;

  bool get isReady => status == AuthStatus.ready;
}

class AuthController extends Notifier<AuthState> {
  Future<void>? _profileLoadInFlight;

  @override
  AuthState build() {
    final sub = supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        _loadProfile();
      } else if (state.status != AuthStatus.loading) {
        state = const AuthState(AuthStatus.needsLogin);
      }
    });
    ref.onDispose(sub.cancel);

    final session = supabase.auth.currentSession;
    if (session != null) {
      Future.microtask(_loadProfile);
      return const AuthState(AuthStatus.loading);
    }
    return const AuthState(AuthStatus.needsLogin);
  }

  Future<void> _loadProfile() async {
    if (_profileLoadInFlight != null) {
      return _profileLoadInFlight!;
    }

    final loadFuture = _performProfileLoad();
    _profileLoadInFlight = loadFuture;
    try {
      await loadFuture;
    } finally {
      if (identical(_profileLoadInFlight, loadFuture)) {
        _profileLoadInFlight = null;
      }
    }
  }

  Future<void> _performProfileLoad() async {
    state = const AuthState(AuthStatus.loading);
    try {
      final profile = await ref.read(backendProvider).getProfile();
      state = AuthState(
        profile.soilType == null || profile.areaLocality == null
            ? AuthStatus.needsOnboarding
            : AuthStatus.ready,
        profile: profile,
      );
    } on ApiException catch (error) {
      state = const AuthState(AuthStatus.needsLogin);
      if (error.isUnauthorized) {
        try {
          await supabase.auth.signOut();
        } on Exception {
          // The UI is already in needsLogin; there is nothing else to do.
        }
      }
    } on Exception {
      // Preserve the session for transient network/server errors.
      state = const AuthState(AuthStatus.needsLogin);
    }
  }

  Future<void> login(String email, String password) async {
    state = const AuthState(AuthStatus.loading);
    try {
      final auth = await ref.read(backendProvider).login(email, password);
      await supabase.auth.setSession(auth.refreshToken);
      await _loadProfile();
    } on Exception {
      state = const AuthState(AuthStatus.needsLogin);
      rethrow;
    }
  }

  Future<void> signup(String email, String password, String name) async {
    state = const AuthState(AuthStatus.loading);
    try {
      final auth = await ref
          .read(backendProvider)
          .signup(email, password, name);
      await supabase.auth.setSession(auth.refreshToken);
      await _loadProfile();
    } on Exception {
      state = const AuthState(AuthStatus.needsLogin);
      rethrow;
    }
  }

  Future<void> signupVendor(String email, String password, String name) async {
    state = const AuthState(AuthStatus.loading);
    try {
      final backend = ref.read(backendProvider);
      final auth = await backend.signup(email, password, name);
      await supabase.auth.setSession(auth.refreshToken);
      await _loadProfile();
      try {
        await backend.vendorSignup();
      } on ApiException catch (error) {
        if (error.statusCode != 409) rethrow;
      }
      state = AuthState(AuthStatus.ready, profile: state.profile);
    } on Exception {
      state = const AuthState(AuthStatus.needsLogin);
      rethrow;
    }
  }

  Future<void> completeOnboarding({
    required String phone,
    required String soilType,
    required String areaLocality,
  }) async {
    final backend = ref.read(backendProvider);
    await backend.updateSettings(
      AppSettings(soilType: soilType, areaLocality: areaLocality),
    );
    await backend.updateAccount(phone: phone);
    final profile = state.profile;
    state = AuthState(
      AuthStatus.ready,
      profile: profile == null
          ? null
          : FarmerProfile(
              id: profile.id,
              name: profile.name,
              phone: phone,
              email: profile.email,
              soilType: soilType,
              areaLocality: areaLocality,
            ),
    );
  }

  Future<void> signOut() => supabase.auth.signOut();
}

final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

// ---------------------------------------------------------------------------
// Farms
// ---------------------------------------------------------------------------

class FarmsState {
  const FarmsState({
    this.farms = const [],
    this.currentFarmId,
    this.loading = false,
  });

  final List<Farm> farms;
  final String? currentFarmId;
  final bool loading;

  Farm? get currentFarm {
    for (final f in farms) {
      if (f.id == currentFarmId) return f;
    }
    return farms.isEmpty ? null : farms.first;
  }
}

class FarmController extends Notifier<FarmsState> {
  @override
  FarmsState build() {
    Future.microtask(load);
    return const FarmsState();
  }

  Future<void> load() async {
    state = FarmsState(
      farms: state.farms,
      currentFarmId: state.currentFarmId,
      loading: true,
    );
    try {
      final farms = await ref.read(backendProvider).getFarms();
      state = FarmsState(farms: farms, currentFarmId: state.currentFarmId);
    } catch (_) {
      state = FarmsState(
        farms: state.farms,
        currentFarmId: state.currentFarmId,
      );
    }
  }

  void select(String farmId) {
    state = FarmsState(farms: state.farms, currentFarmId: farmId);
  }

  Future<void> create(String name) async {
    final farm = await ref.read(backendProvider).createFarm(name);
    state = FarmsState(farms: [farm, ...state.farms], currentFarmId: farm.id);
  }
}

final farmsProvider = NotifierProvider<FarmController, FarmsState>(
  FarmController.new,
);

// ---------------------------------------------------------------------------
// Offline-aware data (motor status, recommendations)
// ---------------------------------------------------------------------------

final motorStatusProvider =
    FutureProvider.family<OfflineResult<MotorStatus>, String>((
      ref,
      farmId,
    ) async {
      final backend = ref.watch(backendProvider);
      final cache = ref.watch(cacheProvider);
      try {
        final json = await backend.getMotorStatusJson(farmId);
        await cache.putMotorStatus(farmId, json);
        return OfflineResult(MotorStatus.fromJson(json), fromCache: false);
      } catch (_) {
        final cached = await cache.getMotorStatus(farmId);
        if (cached == null) rethrow;
        return OfflineResult(
          MotorStatus.fromJson(cached.data),
          fromCache: true,
          savedAt: cached.savedAt,
        );
      }
    });

final recommendationsProvider =
    FutureProvider.family<OfflineResult<Recommendations>, String>((
      ref,
      farmId,
    ) async {
      final backend = ref.watch(backendProvider);
      final cache = ref.watch(cacheProvider);
      try {
        final json = await backend.getRecommendationsJson(farmId);
        await cache.putRecommendations(farmId, json);
        return OfflineResult(Recommendations.fromJson(json), fromCache: false);
      } catch (_) {
        final cached = await cache.getRecommendations(farmId);
        if (cached == null) rethrow;
        return OfflineResult(
          Recommendations.fromJson(cached.data),
          fromCache: true,
          savedAt: cached.savedAt,
        );
      }
    });

// ---------------------------------------------------------------------------
// Simple server data
// ---------------------------------------------------------------------------

final waterSavedProvider = FutureProvider<WaterSaved>((ref) {
  return ref.watch(backendProvider).getWaterSaved();
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  return ref.watch(backendProvider).getNotifications();
});

final marketRequestsProvider = FutureProvider<List<DemandRequest>>((ref) {
  return ref.watch(backendProvider).getDemandRequests();
});

final settingsProvider = FutureProvider<AppSettings>((ref) {
  return ref.watch(backendProvider).getSettings();
});

final fieldsProvider = FutureProvider.family<List<FieldArea>, String>((
  ref,
  farmId,
) {
  return ref.watch(backendProvider).getFields(farmId);
});

/// Weather for the selected farm, plus the latest irrigation decision.
/// Never throws: on any failure it returns empty data so the Home screen
/// degrades gracefully instead of crashing.
final farmWeatherProvider = FutureProvider.family<WeatherInfo, String>((
  ref,
  farmId,
) async {
  try {
    return await ref.watch(backendProvider).getFarmWeather(farmId);
  } catch (_) {
    return WeatherInfo();
  }
});

final accountProvider = FutureProvider<AccountInfo>((ref) {
  return ref.watch(backendProvider).getAccount();
});

final vendorRequestsProvider = FutureProvider<List<VendorRequest>>((ref) {
  return ref.watch(backendProvider).vendorGetRequests();
});

final vendorOpportunitiesProvider = FutureProvider<List<DemandRequest>>((ref) {
  return ref.watch(backendProvider).vendorOpportunities();
});

final impactProvider = FutureProvider.family<ImpactMetrics, String>((
  ref,
  farmId,
) async {
  return ref.watch(backendProvider).getImpact(farmId);
});

final inventoryProvider = FutureProvider<List<InventoryItem>>((ref) {
  return ref.watch(backendProvider).getInventory();
});

// ---------------------------------------------------------------------------
// Realtime notifications
// ---------------------------------------------------------------------------

class RealtimeController extends Notifier<int> {
  RealtimeChannel? _channel;

  @override
  int build() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return 0;
    _channel = supabase
        .channel('notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'farmer_id',
            value: uid,
          ),
          callback: (payload) {
            ref.invalidate(notificationsProvider);
            state++;
          },
        )
        .subscribe();
    ref.onDispose(() {
      supabase.removeChannel(_channel!);
    });
    return 0;
  }
}

final realtimeController = NotifierProvider<RealtimeController, int>(
  RealtimeController.new,
);
