import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../core/i18n/app_language.dart';

enum ActionKind { overdue, dueSoon, leaseEnding }

/// One line in the "Action required" queue (vacant rooms are not listed).
class ActionItem {
  const ActionItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.charge,
    this.tenantId,
  });
  final ActionKind kind;
  final String title;
  final String subtitle;
  final ChargeView? charge;
  final int? tenantId;
}

/// One bar group in the dashboard trend chart (one calendar month).
class MonthlyPoint {
  const MonthlyPoint({
    required this.month,
    required this.billed,
    required this.collected,
  });

  /// First day of the month.
  final DateTime month;

  /// Invoiced with a due date in this month.
  final int billed;

  /// Money received (payment date) in this month.
  final int collected;
}

class DashboardData {
  const DashboardData({
    required this.collected,
    required this.billed,
    required this.outstanding,
    required this.overdueAmount,
    required this.occupied,
    required this.rentable,
    required this.vacant,
    required this.rooms,
    required this.actions,
    required this.overdueCharges,
    required this.monthly,
  });

  /// Money received this calendar month.
  final int collected;

  /// Total invoiced with a due date in this calendar month.
  final int billed;

  /// Everything still unpaid (all months).
  final int outstanding;
  final int overdueAmount;

  final int occupied;
  final int rentable;
  final int vacant;
  final List<RoomOverview> rooms;
  final List<ActionItem> actions;
  final List<ChargeView> overdueCharges;

  /// Last [kTrendMonths] months, oldest first (the last one is this month).
  final List<MonthlyPoint> monthly;

  int get occupancyPercent =>
      rentable == 0 ? 0 : ((occupied * 100) / rentable).round();
}

/// Days before a due date that an invoice shows up as "due soon".
const int kDueSoonDays = 3;
const int kLeaseWarningDaysDashboard = 30;

/// How many months the dashboard chart covers.
const int kTrendMonths = 6;

final dashboardProvider =
    FutureProvider.autoDispose<DashboardData>((ref) async {
  final rooms = await ref.watch(roomOverviewsProvider.future);
  final charges = await ref.watch(chargesProvider(null).future);
  final tenants = await ref.watch(tenantOverviewsProvider.future);
  final collected = await ref.watch(collectedThisMonthProvider.future);

  final today = todayDate();
  final monthStart = DateTime(today.year, today.month, 1);
  final nextMonth = DateTime(today.year, today.month + 1, 1);

  var billed = 0;
  var outstanding = 0;
  var overdueAmount = 0;
  final overdue = <ChargeView>[];
  final soon = <ChargeView>[];

  for (final v in charges) {
    final c = v.charge;
    if (!c.dueDate.isBefore(monthStart) && c.dueDate.isBefore(nextMonth)) {
      billed += c.amount;
    }
    if (c.remaining > 0) {
      outstanding += c.remaining;
      if (c.dueDate.isBefore(today)) {
        overdueAmount += c.remaining;
        overdue.add(v);
      } else if (!c.dueDate.isAfter(addDays(today, kDueSoonDays))) {
        soon.add(v);
      }
    }
  }
  overdue.sort((a, b) => a.charge.dueDate.compareTo(b.charge.dueDate));
  soon.sort((a, b) => a.charge.dueDate.compareTo(b.charge.dueDate));

  final actions = <ActionItem>[];
  for (final v in overdue) {
    final days = today.difference(v.charge.dueDate).inDays;
    actions.add(ActionItem(
      kind: ActionKind.overdue,
      title: tr('Remind {room} · {tenant}',
          {'room': v.roomName, 'tenant': v.tenantName}),
      subtitle: tr(
          days == 1 ? '{amount} · {n} day overdue' : '{amount} · {n} days overdue',
          {'amount': rp(v.charge.remaining), 'n': days}),
      charge: v,
    ));
  }
  for (final v in soon) {
    final days = v.charge.dueDate.difference(today).inDays;
    actions.add(ActionItem(
      kind: ActionKind.dueSoon,
      title: '${v.roomName} · ${v.tenantName}',
      subtitle: tr(
          days == 0
              ? '{amount} · due today'
              : (days == 1
                  ? '{amount} · due in {n} day'
                  : '{amount} · due in {n} days'),
          {'amount': rp(v.charge.remaining), 'n': days}),
      charge: v,
    ));
  }

  final endings = <(int, TenantOverview)>[];
  for (final o in tenants) {
    final t = o.tenant;
    if (!t.isActive || t.endDate == null) continue;
    final left = t.endDate!.difference(today).inDays;
    if (left >= 0 && left <= kLeaseWarningDaysDashboard) endings.add((left, o));
  }
  endings.sort((a, b) => a.$1.compareTo(b.$1));
  for (final e in endings) {
    final t = e.$2.tenant;
    actions.add(ActionItem(
      kind: ActionKind.leaseEnding,
      title: '${t.roomName} · ${t.name}',
      subtitle: e.$1 == 0
          ? tr('Lease ends today')
          : tr(
              e.$1 == 1
                  ? 'Lease ends in {n} day ({date})'
                  : 'Lease ends in {n} days ({date})',
              {'n': e.$1, 'date': fmtDate(t.endDate)}),
      tenantId: t.id,
    ));
  }

  var occupied = 0;
  var vacant = 0;
  var rentable = 0;
  for (final r in rooms) {
    if (r.room.status == RoomStatus.maintenance) continue;
    rentable++;
    if (r.tenants.isNotEmpty) {
      occupied++;
    } else {
      vacant++;
    }
  }
  // Vacant rooms are shown in the Occupancy card and the building overview,
  // not in the action queue.

  // Billed vs collected for the last few months (chart at the bottom).
  final repo = ref.read(repoProvider);
  final monthly = <MonthlyPoint>[];
  for (var i = kTrendMonths - 1; i >= 0; i--) {
    final start = DateTime(today.year, today.month - i, 1);
    final end = DateTime(start.year, start.month + 1, 1);
    var billedInMonth = 0;
    for (final v in charges) {
      final d = v.charge.dueDate;
      if (!d.isBefore(start) && d.isBefore(end)) billedInMonth += v.charge.amount;
    }
    monthly.add(MonthlyPoint(
      month: start,
      billed: billedInMonth,
      collected: await repo.collectedBetween(start, end),
    ));
  }

  return DashboardData(
    collected: collected,
    billed: billed,
    outstanding: outstanding,
    overdueAmount: overdueAmount,
    occupied: occupied,
    rentable: rentable,
    vacant: vacant,
    rooms: rooms,
    actions: actions,
    overdueCharges: overdue,
    monthly: monthly,
  );
});

final lastBackupProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(repoProvider).getLastBackup();
});
