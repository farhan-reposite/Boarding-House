import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/i18n/app_language.dart';
import '../../core/icons.dart';
import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../providers.dart';
import 'export_service.dart';

/// Bottom sheet to export payments: choose the period (month / year / all)
/// and the file type (Excel or PDF).
Future<void> showExportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ExportSheet(),
  );
}

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet();

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  ExportScope _scope = ExportScope.month;
  ExportFormat _format = ExportFormat.xlsx;
  late int _year = todayDate().year;
  late int _month = todayDate().month;
  bool _busy = false;

  ExportPeriod get _period => switch (_scope) {
        ExportScope.month => ExportPeriod.month(_year, _month),
        ExportScope.year => ExportPeriod.year(_year),
        ExportScope.all => ExportPeriod.all(),
      };

  /// First and last month that have invoices (or today, whichever is later).
  (DateTime, DateTime) _bounds(List<ChargeView> all) {
    final today = todayDate();
    var first = DateTime(today.year, today.month, 1);
    var last = first;
    for (final v in all) {
      final d = DateTime(v.charge.dueDate.year, v.charge.dueDate.month, 1);
      if (d.isBefore(first)) first = d;
      if (d.isAfter(last)) last = d;
    }
    return (first, last);
  }

  void _shift(int delta, List<ChargeView> all) {
    final (first, last) = _bounds(all);
    final next = _scope == ExportScope.month
        ? DateTime(_year, _month + delta, 1)
        : DateTime(_year + delta, _month, 1);
    final lo = _scope == ExportScope.month
        ? first
        : DateTime(first.year, 1, 1);
    final hi = _scope == ExportScope.month ? last : DateTime(last.year, 12, 1);
    if (next.isBefore(lo) || next.isAfter(hi)) return;
    setState(() {
      _year = next.year;
      _month = next.month;
    });
  }

  Future<void> _export(List<ChargeView> all) async {
    setState(() => _busy = true);
    try {
      final profile = await ref.read(repoProvider).getProfile();
      await ExportService.exportAndShare(
        all: all,
        period: _period,
        format: _format,
        kostName: profile.name,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        snack(context, tr('Could not create the files: {error}', {'error': e}));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = ref.watch(chargesProvider(null)).valueOrNull ?? const <ChargeView>[];
    final period = _period;
    final rows = ExportService.filter(all, period);
    final sum = ExportService.summarize(rows);
    final locale = AppLang.current.dateLocale;

    final stepperLabel = _scope == ExportScope.month
        ? DateFormat('MMMM yyyy', locale).format(DateTime(_year, _month, 1))
        : '$_year';

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Export payments'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr('Invoices are matched by their due date.'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Text(tr('Period'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ExportScope>(
                segments: [
                  ButtonSegment(
                      value: ExportScope.month, label: Text(tr('Month'))),
                  ButtonSegment(
                      value: ExportScope.year, label: Text(tr('Year'))),
                  ButtonSegment(value: ExportScope.all, label: Text(tr('All'))),
                ],
                selected: {_scope},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _scope = s.first),
              ),
            ),
            if (_scope != ExportScope.all) ...[
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _shift(-1, all),
                    ),
                    Expanded(
                      child: Text(
                        stepperLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _shift(1, all),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(tr('File type'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ExportFormat>(
                segments: [
                  ButtonSegment(
                    value: ExportFormat.xlsx,
                    label: const Text('Excel'),
                    icon: const Icon(Ph.table),
                  ),
                  ButtonSegment(
                    value: ExportFormat.pdf,
                    label: const Text('PDF'),
                    icon: const Icon(Ph.filePdf),
                  ),
                ],
                selected: {_format},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: rows.isEmpty
                  ? Text(tr('No invoices in this period.'),
                      style: TextStyle(color: scheme.onSurfaceVariant))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(rows.length == 1
                                  ? '{n} invoice in {period}'
                                  : '{n} invoices in {period}',
                              {'n': rows.length, 'period': period.label}),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tr('Billed')} ${rp(sum.billed)}  |  '
                          '${tr('Collected')} ${rp(sum.collected)}',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_busy || rows.isEmpty) ? null : () => _export(all),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_format == ExportFormat.xlsx ? Ph.table : Ph.filePdf),
                label: Text(tr('Export')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
