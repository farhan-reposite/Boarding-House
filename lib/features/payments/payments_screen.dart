import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/kost_logo.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../providers.dart';
import 'charge_detail_screen.dart';
import 'export_sheet.dart';
import 'invoice_service.dart';
import 'mark_paid.dart';
import 'reminder_queue.dart';
import '../../core/i18n/app_language.dart';

enum _Filter {
  unpaid('Unpaid'),
  overdue('Overdue'),
  paid('Paid'),
  all('All');

  const _Filter(this._key);
  final String _key;
  String get label => tr(_key);
}

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  _Filter _filter = _Filter.unpaid;

  /// Optional due-date range (inclusive) set with the date chip.
  DateTimeRange? _range;
  final Set<int> _selected = {};
  List<ChargeView> _lastShown = const [];
  bool _busy = false;

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(int id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  List<ChargeView> _selectedViews() =>
      _lastShown.where((v) => _selected.contains(v.charge.id)).toList();

  Future<void> _remindSelected() async {
    final views = _selectedViews().where((v) => v.charge.remaining > 0).toList();
    if (views.isEmpty) {
      snack(context, tr('Selected invoices are already paid.'));
      return;
    }
    final profile = await ref.read(repoProvider).getProfile();
    if (!mounted) return;
    await showReminderQueue(context, views, profile);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _markPaidSelected() async {
    final views = _selectedViews().where((v) => v.charge.remaining > 0).toList();
    if (views.isEmpty) {
      snack(context, tr('Selected invoices are already paid.'));
      return;
    }
    final total = views.fold<int>(0, (a, v) => a + v.charge.remaining);
    var method = 'Cash';
    var paidOn = todayDate();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr('Mark {n} invoices as paid?', {'n': views.length})),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Records {amount} received in full.', {'amount': rp(total)})),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: paidOn,
                    firstDate: DateTime(2015),
                    lastDate: todayDate(),
                  );
                  if (picked != null) setLocal(() => paidOn = dateOnly(picked));
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: tr('Payment date'),
                    suffixIcon: const Icon(Ph.calendarBlank),
                  ),
                  child: Text(fmtDate(paidOn)),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in kPaymentMethods)
                    ChoiceChip(
                      label: Text(tr(m)),
                      selected: method == m,
                      onSelected: (_) => setLocal(() => method = m),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Mark paid'))),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final repo = ref.read(repoProvider);
    var done = 0;
    try {
      for (final v in views) {
        await repo.addPayment(
          chargeId: v.charge.id,
          amount: v.charge.remaining,
          date: paidOn,
          method: method,
          note: tr('Bulk payment'),
        );
        done++;
      }
    } on KostException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      notifyChanged(ref);
      if (mounted) {
        setState(() {
          _busy = false;
          _selected.clear();
        });
        if (done > 0) snack(context, tr('{n} invoices marked as paid.', {'n': done}));
      }
    }
  }

  Future<void> _receiptsSelected() async {
    final views = _selectedViews();
    if (views.isEmpty) return;
    setState(() => _busy = true);
    try {
      final profile = await ref.read(repoProvider).getProfile();
      await InvoiceService.shareMany(views, profile);
    } catch (e) {
      if (mounted) snack(context, tr('Could not create the files: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _rangeLabel {
    final r = _range;
    if (r == null) return tr('Any date');
    if (r.start == r.end) return fmtDate(r.start);
    return '${fmtDate(r.start)} - ${fmtDate(r.end)}';
  }

  Future<void> _pickRange() async {
    final today = todayDate();
    final thisMonthEnd = DateTime(today.year, today.month + 1, 0);
    final presets = <String, DateTimeRange>{
      'this': DateTimeRange(
          start: DateTime(today.year, today.month, 1), end: thisMonthEnd),
      'last': DateTimeRange(
          start: DateTime(today.year, today.month - 1, 1),
          end: DateTime(today.year, today.month, 0)),
      'last3': DateTimeRange(
          start: DateTime(today.year, today.month - 2, 1), end: thisMonthEnd),
    };

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Ph.calendarBlank),
              title: Text(tr('This month')),
              onTap: () => Navigator.pop(ctx, 'this'),
            ),
            ListTile(
              leading: const Icon(Ph.calendarBlank),
              title: Text(tr('Last month')),
              onTap: () => Navigator.pop(ctx, 'last'),
            ),
            ListTile(
              leading: const Icon(Ph.calendarBlank),
              title: Text(tr('Last 3 months')),
              onTap: () => Navigator.pop(ctx, 'last3'),
            ),
            ListTile(
              leading: const Icon(Ph.pencilSimple),
              title: Text(tr('Pick dates...')),
              onTap: () => Navigator.pop(ctx, 'custom'),
            ),
            if (_range != null)
              ListTile(
                leading: const Icon(Ph.funnelX),
                title: Text(tr('Clear date filter')),
                onTap: () => Navigator.pop(ctx, 'clear'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'clear') {
      setState(() => _range = null);
    } else if (choice == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2015),
        lastDate: DateTime(2100),
        initialDateRange: _range,
      );
      if (picked != null && mounted) {
        setState(() => _range =
            DateTimeRange(start: dateOnly(picked.start), end: dateOnly(picked.end)));
      }
    } else {
      setState(() => _range = presets[choice]);
    }
  }

  AppBar _buildAppBar() {
    if (_selecting) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Ph.x),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text(tr('{n} selected', {'n': _selected.length})),
        actions: [
          IconButton(
            tooltip: tr('Select all shown'),
            icon: const Icon(Ph.selectionAll),
            onPressed: () => setState(() =>
                _selected.addAll(_lastShown.map((v) => v.charge.id))),
          ),
          IconButton(
            tooltip: tr('Send WhatsApp reminders'),
            icon: const Icon(Ph.megaphone),
            onPressed: _busy ? null : _remindSelected,
          ),
          IconButton(
            tooltip: tr('Mark as paid'),
            icon: const Icon(Ph.checks),
            onPressed: _busy ? null : _markPaidSelected,
          ),
          IconButton(
            tooltip: tr('Share invoices / receipts (PDF)'),
            icon: const Icon(Ph.filePdf),
            onPressed: _busy ? null : _receiptsSelected,
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      );
    }
    return AppBar(
      leadingWidth: 56,
      leading: const Padding(
        padding: EdgeInsets.all(12),
        child: KostLogo(size: 28),
      ),
      title: Text(tr('Payments')),
      actions: [
        IconButton(
          tooltip: tr('Export payments'),
          icon: const Icon(Ph.table),
          onPressed: () => showExportSheet(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final charges = ref.watch(chargesProvider(null));
    final collected = ref.watch(collectedThisMonthProvider).valueOrNull;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
      appBar: _buildAppBar(),
      body: charges.ui(data: (all) {
        final today = todayDate();
        var outstanding = 0;
        var overdueAmount = 0;
        for (final v in all) {
          final r = v.charge.remaining;
          if (r > 0) {
            outstanding += r;
            if (v.charge.dueDate.isBefore(today)) overdueAmount += r;
          }
        }

        final range = _range;
        final shown = all.where((v) {
          final c = v.charge;
          if (range != null &&
              (c.dueDate.isBefore(range.start) || c.dueDate.isAfter(range.end))) {
            return false;
          }
          switch (_filter) {
            case _Filter.unpaid:
              return c.remaining > 0;
            case _Filter.overdue:
              return c.remaining > 0 && c.dueDate.isBefore(today);
            case _Filter.paid:
              return c.remaining == 0;
            case _Filter.all:
              return true;
          }
        }).toList();
        if (_filter == _Filter.unpaid || _filter == _Filter.overdue) {
          shown.sort((a, b) => a.charge.dueDate.compareTo(b.charge.dueDate));
        }
        _lastShown = shown;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _Stat(label: tr('Outstanding'), value: rp(outstanding)),
                  _Stat(
                    label: tr('Overdue'),
                    value: rp(overdueAmount),
                    danger: overdueAmount > 0,
                  ),
                  _Stat(
                    label: tr('Collected this month'),
                    value: collected == null ? '...' : rp(collected),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      avatar: const Icon(Ph.calendarBlank, size: 18),
                      label: Text(_rangeLabel),
                      selected: _range != null,
                      onPressed: _pickRange,
                      onDeleted:
                          _range == null ? null : () => setState(() => _range = null),
                      deleteIcon: const Icon(Ph.x, size: 16),
                    ),
                  ),
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f.label),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? EmptyState(
                      icon: Ph.receipt,
                      message: all.isEmpty
                          ? tr('No invoices yet.\nThey are created automatically when you add a tenant.')
                          : tr('Nothing here.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final v = shown[i];
                        return ChargeTile(
                          view: v,
                          selected: _selected.contains(v.charge.id),
                          onLongPress: () => _toggle(v.charge.id),
                          onTapOverride:
                              _selecting ? () => _toggle(v.charge.id) : null,
                        );
                      },
                    ),
            ),
          ],
        );
      }),
    ));
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.danger = false});
  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: danger ? scheme.error : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One invoice row, used here and on the tenant detail page.
///
/// On the Payments list ([showTenant] true) each invoice is its own card with
/// a one-tap "Mark paid" button. On the tenant page it stays a plain row
/// inside that page's section card.
class ChargeTile extends ConsumerWidget {
  const ChargeTile({
    super.key,
    required this.view,
    this.showTenant = true,
    this.selected = false,
    this.onLongPress,
    this.onTapOverride,
  });
  final ChargeView view;
  final bool showTenant;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onTapOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final c = view.charge;
    final status = c.statusOn(todayDate());
    final period = '${fmtDate(c.dueDate)} – ${fmtDate(c.periodEnd)}';
    final amountLine = (c.paidAmount > 0 && c.remaining > 0)
        ? tr('Paid {paid} of {total}',
            {'paid': rp(c.paidAmount), 'total': rp(c.amount)})
        : rp(c.amount);
    final canPay = c.remaining > 0;

    void open() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChargeDetailScreen(chargeId: c.id)),
        );

    final paidButton = canPay
        ? FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
              visualDensity: VisualDensity.compact,
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Ph.check, size: 16),
            label: Text(tr('Mark paid')),
            onPressed: () => quickMarkPaid(context, ref, view),
          )
        : null;

    if (!showTenant) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(period),
        subtitle: Text(amountLine),
        trailing: PaymentStatusPill(status),
        onTap: onTapOverride ?? open,
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      clipBehavior: Clip.antiAlias,
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.6)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.6),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTapOverride ?? open,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (selected) ...[
                Icon(Ph.checkCircle, color: scheme.primary),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${view.tenantName} · ${view.roomName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(period,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                    Text(amountLine,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PaymentStatusPill(status),
                  if (paidButton != null) ...[
                    const SizedBox(height: 8),
                    paidButton,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
