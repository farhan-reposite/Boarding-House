import 'package:flutter/material.dart';
import '../../core/icons.dart';

import '../../core/utils/format.dart';
import '../../core/utils/launch.dart';
import '../../data/models.dart';
import 'invoice_service.dart';
import '../../core/i18n/app_language.dart';

/// Walks through a list of invoices one tenant at a time. Each "Send" opens
/// WhatsApp with the reminder already written; coming back to the app shows
/// the next tenant. WhatsApp can't be driven automatically, so this is the
/// fastest safe way to remind many people.
Future<void> showReminderQueue(
  BuildContext context,
  List<ChargeView> charges,
  KostProfile profile,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReminderQueue(charges: charges, profile: profile),
  );
}

class _ReminderQueue extends StatefulWidget {
  const _ReminderQueue({required this.charges, required this.profile});
  final List<ChargeView> charges;
  final KostProfile profile;

  @override
  State<_ReminderQueue> createState() => _ReminderQueueState();
}

class _ReminderQueueState extends State<_ReminderQueue> {
  int _index = 0;
  int _sent = 0;

  @override
  Widget build(BuildContext context) {
    final total = widget.charges.length;
    if (_index >= total) {
      return AlertDialog(
        title: Text(tr('All done')),
        content: Text(tr('{sent} of {total} reminders opened in WhatsApp.',
            {'sent': _sent, 'total': total})),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Close')),
          ),
        ],
      );
    }
    final v = widget.charges[_index];
    final hasPhone = normalizePhone(v.tenantPhone).isNotEmpty;
    final message = InvoiceService.message(v, widget.profile);

    return AlertDialog(
      title: Text(tr('Reminder {i} of {total}', {'i': _index + 1, 'total': total})),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: _index / total),
            const SizedBox(height: 12),
            Text('${v.roomName} · ${v.tenantName}',
                style: Theme.of(context).textTheme.titleMedium),
            Text(hasPhone ? v.tenantPhone : tr('No phone number saved'),
                style: TextStyle(
                    color: hasPhone
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(message, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Stop')),
        ),
        TextButton(
          onPressed: () => setState(() => _index++),
          child: Text(tr('Skip')),
        ),
        FilledButton.icon(
          onPressed: hasPhone
              ? () async {
                  await openWhatsApp(context, v.tenantPhone, message);
                  if (!mounted) return;
                  setState(() {
                    _sent++;
                    _index++;
                  });
                }
              : null,
          icon: const Icon(Ph.paperPlaneTilt),
          label: Text(tr('Send')),
        ),
      ],
    );
  }
}
