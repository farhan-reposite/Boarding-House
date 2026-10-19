import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/database.dart';
import 'core/i18n/app_language.dart';
import 'core/utils/date_helpers.dart';
import 'data/models.dart';
import 'data/repository.dart';

final repoProvider =
    Provider<KostRepository>((ref) => KostRepository(AppDatabase.instance));

// ------------------------------------------------------------- appearance

/// The current light/dark/system setting. main() overrides its initial
/// value with whatever was last saved, so there's no flash of the wrong
/// theme on launch; the settings screen updates it (and persists the
/// change) whenever the user picks a different option.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// The UI language. main() overrides the initial value with the saved one.
/// Use [changeLanguage] to switch (it also saves the choice).
final languageProvider =
    StateProvider<AppLanguage>((ref) => AppLanguage.id);

Future<void> changeLanguage(WidgetRef ref, AppLanguage language) async {
  // Set the global first so everything rebuilt by the provider change
  // already reads the new language.
  AppLang.current = language;
  await ref.read(repoProvider).setLanguageSetting(language.code);
  ref.read(languageProvider.notifier).state = language;
  // Providers that build text (e.g. the dashboard action list) recompute.
  notifyChanged(ref);
}

/// Which bottom-bar / sidebar tab is showing (0 = Home ... 4 = Settings).
/// Lives in a provider so the first-run tutorial can switch tabs.
final shellTabProvider = StateProvider<int>((ref) => 0);

ThemeMode themeModeFromSetting(String value) => switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

String themeModeToSetting(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

/// Every data provider watches this. After any write, call [notifyChanged]
/// and all screens refresh themselves.
final dataVersionProvider = StateProvider<int>((ref) => 0);

void notifyChanged(WidgetRef ref) {
  ref.read(dataVersionProvider.notifier).state++;
}

final roomOverviewsProvider =
    FutureProvider.autoDispose<List<RoomOverview>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).getRoomOverviews();
});

final roomProvider =
    FutureProvider.autoDispose.family<Room?, int>((ref, id) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).getRoom(id);
});

final roomPhotosProvider =
    FutureProvider.autoDispose.family<List<RoomPhoto>, int>((ref, roomId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).getRoomPhotos(roomId);
});

final tenantOverviewsProvider =
    FutureProvider.autoDispose<List<TenantOverview>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).getTenantOverviews();
});

final tenantOverviewProvider =
    FutureProvider.autoDispose.family<TenantOverview?, int>((ref, tenantId) async {
  ref.watch(dataVersionProvider);
  final all = await ref.read(repoProvider).getTenantOverviews();
  return all.where((o) => o.tenant.id == tenantId).firstOrNull;
});

/// All active tenants currently living in a room (a room may hold more than
/// one when its capacity is greater than 1).
final roomTenantsProvider =
    FutureProvider.autoDispose.family<List<TenantOverview>, int>((ref, roomId) async {
  ref.watch(dataVersionProvider);
  final all = await ref.read(repoProvider).getTenantOverviews();
  return all
      .where((o) => o.tenant.isActive && o.tenant.roomId == roomId)
      .toList();
});

final depositsProvider =
    FutureProvider.autoDispose.family<List<DepositEntry>, int>((ref, tenantId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).getDeposits(tenantId);
});

final depositHeldProvider =
    FutureProvider.autoDispose.family<int, int>((ref, tenantId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).depositHeld(tenantId);
});

/// All invoices (key = null) or one tenant's invoices.
final chargesProvider =
    FutureProvider.autoDispose.family<List<ChargeView>, int?>((ref, tenantId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).getCharges(tenantId: tenantId);
});

final chargeProvider =
    FutureProvider.autoDispose.family<ChargeView?, int>((ref, id) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).getCharge(id);
});

final paymentsProvider =
    FutureProvider.autoDispose.family<List<Payment>, int>((ref, chargeId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).getPayments(chargeId);
});

final collectedThisMonthProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(dataVersionProvider);
  final now = todayDate();
  final from = DateTime(now.year, now.month, 1);
  final to = DateTime(now.year, now.month + 1, 1);
  return ref.read(repoProvider).collectedBetween(from, to);
});

/// The kost name from Settings (shown in the dashboard header).
final profileNameProvider = FutureProvider.autoDispose<String>((ref) async {
  ref.watch(dataVersionProvider);
  return (await ref.read(repoProvider).getProfile()).name;
});
