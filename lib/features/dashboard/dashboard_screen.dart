import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../core/utils/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/kost_logo.dart';
import '../../providers.dart';
import '../payments/charge_detail_screen.dart';
import '../payments/invoice_service.dart';
import '../payments/mark_paid.dart';
import '../payments/reminder_queue.dart';
import '../rooms/room_matrix.dart';
import '../tenants/tenant_detail_screen.dart';
import 'insights.dart';
import '../../core/i18n/app_language.dart';

/// The landlord's home screen: money, occupancy, what needs doing today.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key, required this.onOpenTab});

  /// Switches the bottom navigation: 1 = Rooms, 4 = Settings.
  final ValueChanged<int> onOpenTab;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _showAll = false;

  Future<void> _remind(ActionItem item) async {
    final v = item.charge;
    if (v == null) return;
    final profile = await ref.read(repoProvider).getProfile();
    if (!mounted) return;
    await openWhatsApp(context, v.tenantPhone, InvoiceService.message(v, profile));
  }

  Future<void> _remindAll(DashboardData d) async {
    final profile = await ref.read(repoProvider).getProfile();
    if (!mounted) return;
    await showReminderQueue(context, d.overdueCharges, profile);
  }

  void _open(ActionItem item) {
    final nav = Navigator.of(context);
    switch (item.kind) {
      case ActionKind.overdue:
      case ActionKind.dueSoon:
        nav.push(MaterialPageRoute(
            builder: (_) => ChargeDetailScreen(chargeId: item.charge!.charge.id)));
      case ActionKind.leaseEnding:
        nav.push(MaterialPageRoute(
            builder: (_) => TenantDetailScreen(tenantId: item.tenantId!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dashboardProvider);
    final profileName = ref.watch(profileNameProvider).valueOrNull ?? '';

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: const Padding(
          padding: EdgeInsets.all(12),
          child: KostLogo(size: 28),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profileName.isEmpty ? 'Kost Manager' : profileName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(fmtDate(todayDate()),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      body: async.ui(
        data: (d) => RefreshIndicator(
          onRefresh: () async => notifyChanged(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _Kpis(d: d),
              const SizedBox(height: 20),
              _actionSection(context, d),
              const SizedBox(height: 20),
              _buildingSection(context, d),
              const SizedBox(height: 24),
              _TrendCard(points: d.monthly),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionSection(BuildContext context, DashboardData d) {
    final scheme = Theme.of(context).colorScheme;
    final items = d.actions;
    final visible = _showAll ? items : items.take(6).toList();
    final urgent = items.where((a) => a.kind == ActionKind.overdue).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(tr('Action required'),
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            if (items.isNotEmpty)
              Pill(
                label: '${items.length}',
                colors: toneColors(
                    context, urgent > 0 ? Tone.danger : Tone.warning),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (d.overdueCharges.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.tonalIcon(
              onPressed: () => _remindAll(d),
              icon: const Icon(Ph.megaphone),
              label: Text(tr('Remind all {n} overdue', {'n': d.overdueCharges.length})),
            ),
          ),
        if (items.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Ph.checkCircle, color: toneAccent(Tone.success)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(tr('You are all caught up. Nothing needs attention.'),
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _ActionTile(
                    item: visible[i],
                    onTap: () => _open(visible[i]),
                    onRemind: visible[i].charge == null
                        ? null
                        : () => _remind(visible[i]),
                    onPaid: visible[i].charge == null
                        ? null
                        : () => quickMarkPaid(context, ref, visible[i].charge!),
                  ),
                ],
              ],
            ),
          ),
        if (items.length > 6)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(_showAll ? tr('Show less') : tr('Show all {n}', {'n': items.length})),
            ),
          ),
      ],
    );
  }

  Widget _buildingSection(BuildContext context, DashboardData d) {
    if (d.rooms.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(tr('Building overview'),
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            TextButton(
              onPressed: () => widget.onOpenTab(1),
              child: Text(tr('Open rooms')),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const RoomLegend(),
        const SizedBox(height: 10),
        RoomMatrix(rooms: d.rooms, compact: true),
      ],
    );
  }
}

// ------------------------------------------------------------------- KPIs

class _Kpis extends StatelessWidget {
  const _Kpis({required this.d});
  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final revenue = _KpiCard(
      icon: Ph.money,
      tone: Tone.success,
      hero: true,
      label: tr('Collected this month'),
      value: rp(d.collected),
      footer: d.billed == 0
          ? tr('Nothing billed yet')
          : tr('of {amount} billed', {'amount': rp(d.billed)}),
      progress: d.billed == 0 ? null : (d.collected / d.billed).clamp(0.0, 1.0).toDouble(),
    );
    final occupancy = _KpiCard(
      icon: Ph.buildings,
      tone: Tone.info,
      label: tr('Occupancy'),
      value: '${d.occupancyPercent}%',
      footer: tr('{occupied} of {rentable} rooms · {vacant} vacant', {
        'occupied': d.occupied,
        'rentable': d.rentable,
        'vacant': d.vacant,
      }),
      progress: d.rentable == 0 ? null : d.occupied / d.rentable,
    );
    final debt = _KpiCard(
      icon: Ph.warning,
      tone: d.overdueAmount > 0 ? Tone.danger : Tone.neutral,
      label: tr('Outstanding'),
      value: rp(d.outstanding),
      footer: d.overdueAmount > 0
          ? tr('{amount} overdue', {'amount': rp(d.overdueAmount)})
          : tr('Nothing overdue'),
    );

    return LayoutBuilder(builder: (context, c) {
      // IntrinsicHeight + stretch: every card in a row is as tall as the
      // tallest one (the Outstanding card has no progress bar, so it was
      // shorter than its neighbours).
      if (c.maxWidth >= 640) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: revenue),
              const SizedBox(width: 10),
              Expanded(child: occupancy),
              const SizedBox(width: 10),
              Expanded(child: debt),
            ],
          ),
        );
      }
      return Column(
        children: [
          revenue,
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: occupancy),
                const SizedBox(width: 10),
                Expanded(child: debt),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    required this.footer,
    this.progress,
    this.hero = false,
  });
  final IconData icon;
  final Tone tone;
  final String label;
  final String value;
  final String footer;
  final double? progress;

  /// Dark-green feature card (the main revenue number).
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = hero
        ? StatusColors(dark ? const Color(0xFF1F5240) : kForest, Colors.white)
        : toneColors(context, tone);
    final accent = hero ? kGold : toneAccent(tone);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: colors.fg),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.fg)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(
                        fontSize: hero ? 32 : 26,
                        fontWeight: FontWeight.w800,
                        color: colors.fg)),
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(footer,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.fg)),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- action queue

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.item,
    required this.onTap,
    this.onRemind,
    this.onPaid,
  });
  final ActionItem item;
  final VoidCallback onTap;
  final VoidCallback? onRemind;
  final VoidCallback? onPaid;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (item.kind) {
      ActionKind.overdue => (Tone.danger, Ph.warningCircle),
      ActionKind.dueSoon => (Tone.warning, Ph.clock),
      ActionKind.leaseEnding => (Tone.warning, Ph.calendarX),
    };
    final colors = toneColors(context, tone);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: colors.bg,
        child: Icon(icon, color: colors.fg, size: 20),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.subtitle),
      trailing: (onRemind == null && onPaid == null)
          ? const Icon(Ph.caretRight)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRemind != null)
                  IconButton.filledTonal(
                    tooltip: tr('Remind via WhatsApp'),
                    icon: const Icon(Ph.paperPlaneTilt, size: 18),
                    onPressed: onRemind,
                  ),
                if (onPaid != null) ...[
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: tr('Mark as paid'),
                    icon: const Icon(Ph.check, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: toneAccent(Tone.success),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onPaid,
                  ),
                ],
              ],
            ),
    );
  }
}

// ------------------------------------------------------------------ trend

/// Billed vs collected per month for the last few months.
/// Tap a month to see its numbers.
class _TrendCard extends StatefulWidget {
  const _TrendCard({required this.points});
  final List<MonthlyPoint> points;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = widget.points;
    if (points.isEmpty) return const SizedBox.shrink();

    final selected = (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final sel = points[selected];
    final rate =
        sel.billed == 0 ? null : (sel.collected * 100 / sel.billed).round();
    final locale = AppLang.current.dateLocale;
    final monthLabel = DateFormat('MMMM yyyy', locale).format(sel.month);

    final billedColor = scheme.primary.withValues(alpha: 0.28);
    final collectedColor = scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Income trend'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          tr('Billed vs collected, last {n} months', {'n': points.length}),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    _LegendDot(color: billedColor, label: tr('Billed')),
                    _LegendDot(color: collectedColor, label: tr('Collected')),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, c) {
                  final painter = _TrendPainter(
                    points: points,
                    selected: selected,
                    locale: locale,
                    billedColor: billedColor,
                    collectedColor: collectedColor,
                    gridColor: scheme.outlineVariant,
                    textColor: scheme.onSurfaceVariant,
                    highlightColor:
                        scheme.primaryContainer.withValues(alpha: 0.55),
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      final i = painter.indexAt(d.localPosition, Size(c.maxWidth, 190));
                      if (i != null) setState(() => _selected = i);
                    },
                    child: CustomPaint(
                      size: Size(c.maxWidth, 190),
                      painter: painter,
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(monthLabel,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        tr('Collected {collected} of {billed} billed', {
                          'collected': rp(sel.collected),
                          'billed': rp(sel.billed),
                        }),
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                      if (rate != null)
                        Text(
                          tr('{n}% collected', {'n': rate}),
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.selected,
    required this.locale,
    required this.billedColor,
    required this.collectedColor,
    required this.gridColor,
    required this.textColor,
    required this.highlightColor,
  });

  final List<MonthlyPoint> points;
  final int selected;
  final String locale;
  final Color billedColor;
  final Color collectedColor;
  final Color gridColor;
  final Color textColor;
  final Color highlightColor;

  static const double _left = 44;
  static const double _bottom = 22;
  static const double _top = 8;
  static const int _gridLines = 3;

  int get _maxValue {
    var m = 0;
    for (final p in points) {
      m = math.max(m, math.max(p.billed, p.collected));
    }
    return m;
  }

  /// Rounds the largest value up to a "nice" axis maximum (1, 2, 2.5, 5, 10 x 10^n).
  double get _axisMax {
    final m = _maxValue;
    if (m <= 0) return 1000000;
    final mag = math.pow(10, (math.log(m) / math.ln10).floor()).toDouble();
    final f = m / mag;
    final nice = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10;
    return nice * mag;
  }

  String _short(double v) {
    final id = AppLang.current == AppLanguage.id;
    String fmt(double x) {
      final s = x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
      return id ? s.replaceAll('.', ',') : s;
    }

    if (v >= 1e9) return '${fmt(v / 1e9)} ${id ? 'M' : 'B'}';
    if (v >= 1e6) return '${fmt(v / 1e6)} ${id ? 'jt' : 'M'}';
    if (v >= 1e3) return '${fmt(v / 1e3)} ${id ? 'rb' : 'K'}';
    return v.round().toString();
  }

  void _text(Canvas canvas, String text, Offset at,
      {bool rightAlign = false, bool center = false, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10.5,
          color: textColor,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (rightAlign) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  int? indexAt(Offset p, Size size) {
    final chartW = size.width - _left;
    if (p.dx < _left || p.dx > size.width || points.isEmpty) return null;
    final slot = chartW / points.length;
    return ((p.dx - _left) / slot).floor().clamp(0, points.length - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chartW = size.width - _left;
    final chartH = size.height - _bottom - _top;
    final axisMax = _axisMax;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (var i = 0; i <= _gridLines; i++) {
      final y = _top + chartH * (1 - i / _gridLines);
      canvas.drawLine(Offset(_left, y), Offset(size.width, y), gridPaint);
      _text(canvas, _short(axisMax * i / _gridLines), Offset(_left - 6, y),
          rightAlign: true);
    }

    final slot = chartW / points.length;
    final barW = math.min(slot * 0.28, 20.0);
    const radius = Radius.circular(4);

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final cx = _left + slot * (i + 0.5);

      if (i == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(_left + slot * i + 2, _top - 4, slot - 4,
                chartH + _bottom + 2),
            const Radius.circular(10),
          ),
          Paint()..color = highlightColor,
        );
      }

      void bar(double x, int value, Color color) {
        if (value <= 0) return;
        final h = math.max(2.0, chartH * value / axisMax);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, _top + chartH - h, barW, h),
            topLeft: radius,
            topRight: radius,
          ),
          Paint()..color = color,
        );
      }

      bar(cx - barW - 1.5, p.billed, billedColor);
      bar(cx + 1.5, p.collected, collectedColor);

      _text(canvas, DateFormat('MMM', locale).format(p.month),
          Offset(cx, size.height - _bottom / 2 + 2),
          center: true, bold: i == selected);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.billedColor != billedColor ||
      old.collectedColor != collectedColor ||
      old.textColor != textColor;
}
