import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_language.dart';
import '../../core/icons.dart';
import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../providers.dart';

/// One-step "mark as paid" for a single invoice, without opening its detail
/// page. Shows a small confirmation (date + method, defaulting to today /
/// cash), then records the full remaining balance as a payment.
///
/// Returns true when the payment was recorded.
Future<bool> quickMarkPaid(
    BuildContext context, WidgetRef ref, ChargeView view) async {
  final remaining = view.charge.remaining;
  if (remaining <= 0) return false;

  var method = kPaymentMethods.first;
  var paidOn = todayDate();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(tr('Mark as paid')),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${view.roomName} · ${view.tenantName}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(tr('Records {amount} received in full.',
                  {'amount': rp(remaining)})),
              const SizedBox(height: 16),
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
                runSpacing: 4,
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
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancel'))),
          FilledButton.icon(
              icon: const Icon(Ph.check),
              onPressed: () => Navigator.pop(ctx, true),
              label: Text(tr('Mark paid'))),
        ],
      ),
    ),
  );
  if (ok != true) return false;

  try {
    await ref.read(repoProvider).addPayment(
          chargeId: view.charge.id,
          amount: remaining,
          date: paidOn,
          method: method,
        );
    notifyChanged(ref);
    if (context.mounted) {
      snack(context, tr('Marked as paid.'));
    }
    return true;
  } on KostException catch (e) {
    if (context.mounted) snack(context, e.message);
    return false;
  }
}
