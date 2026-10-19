import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../core/utils/launch.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../providers.dart';
import 'invoice_service.dart';
import '../../core/i18n/app_language.dart';

class ChargeDetailScreen extends ConsumerWidget {
  const ChargeDetailScreen({super.key, required this.chargeId});
  final int chargeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chargeProvider(chargeId));
    final view = async.valueOrNull;

    if (view == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const SizedBox.shrink(),
      );
    }

    final c = view.charge;
    final status = c.statusOn(todayDate());
    final payments = ref.watch(paymentsProvider(chargeId)).valueOrNull ?? [];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(InvoiceService.number(view)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'amount') _editAmount(context, ref, view);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'amount', child: Text(tr('Edit invoice amount'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SectionCard(
            title: tr('Invoice'),
            trailing: PaymentStatusPill(status),
            children: [
              InfoRow(tr('Tenant'), view.tenantName),
              InfoRow(tr('Room'), view.roomName),
              InfoRow(tr('Period'), '${fmtDate(c.dueDate)} – ${fmtDate(c.periodEnd)}'),
              InfoRow(
                tr('Due date'),
                fmtDate(c.dueDate),
                valueColor:
                    status == PaymentStatus.overdue ? scheme.error : null,
              ),
              const Divider(height: 24),
              InfoRow(tr('Amount'), rp(c.amount)),
              InfoRow(tr('Paid'), rp(c.paidAmount)),
              InfoRow(
                tr('Remaining'),
                rp(c.remaining),
                valueColor: c.remaining > 0 ? scheme.error : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.remaining > 0)
                  FilledButton.icon(
                    icon: const Icon(Ph.money),
                    label: Text(tr('Record payment')),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => RecordPaymentSheet(view: view),
                    ),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Ph.filePdf),
                  label: Text(tr('Share invoice')),
                  onPressed: () => _shareInvoice(context, ref, view),
                ),
                if (view.tenantPhone.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Ph.chatCircleText),
                    label: Text(c.remaining > 0
                        ? tr('WhatsApp reminder')
                        : tr('WhatsApp receipt')),
                    onPressed: () => _whatsApp(context, ref, view),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: tr('Payments received'),
            children: [
              if (payments.isEmpty)
                Text(tr('No payments recorded yet.'))
              else
                for (final p in payments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: p.proofPhoto == null
                        ? const Icon(Ph.checkCircle)
                        : PhotoThumb(
                            name: p.proofPhoto,
                            size: 44,
                            onTap: () => openPhoto(context, p.proofPhoto!),
                          ),
                    title: Text(rp(p.amount)),
                    subtitle: Text(
                      '${fmtDate(p.paidOn)} · ${tr(p.method)}${p.note.isEmpty ? '' : '\n${p.note}'}',
                    ),
                    isThreeLine: p.note.isNotEmpty,
                    trailing: IconButton(
                      icon: const Icon(Ph.trash),
                      tooltip: tr('Delete payment'),
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: tr('Delete this payment?'),
                          message:
                              tr('Use this to fix a mistake. The invoice balance will go back up by {amount}.',
                              {'amount': rp(p.amount)}),
                          confirmLabel: tr('Delete'),
                          destructive: true,
                        );
                        if (!ok) return;
                        await ref.read(repoProvider).deletePayment(p);
                        notifyChanged(ref);
                      },
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _shareInvoice(
      BuildContext context, WidgetRef ref, ChargeView view) async {
    try {
      final profile = await ref.read(repoProvider).getProfile();
      await InvoiceService.sharePdf(view, profile);
    } catch (e) {
      if (context.mounted) snack(context, tr('Could not create the invoice: {error}', {'error': e}));
    }
  }

  Future<void> _whatsApp(
      BuildContext context, WidgetRef ref, ChargeView view) async {
    final profile = await ref.read(repoProvider).getProfile();
    if (!context.mounted) return;
    await openWhatsApp(
        context, view.tenantPhone, InvoiceService.message(view, profile));
  }

  Future<void> _editAmount(
      BuildContext context, WidgetRef ref, ChargeView view) async {
    final controller =
        TextEditingController(text: view.charge.amount.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Edit invoice amount')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            prefixText: 'Rp ',
            helperText: tr('For a discount or an extra charge'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parseMoney(controller.text)),
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      await ref.read(repoProvider).updateChargeAmount(view.charge.id, result);
      notifyChanged(ref);
    } on KostException catch (e) {
      if (context.mounted) snack(context, e.message);
    }
  }
}

// -------------------------------------------------------- record payment

class RecordPaymentSheet extends ConsumerStatefulWidget {
  const RecordPaymentSheet({super.key, required this.view});
  final ChargeView view;

  @override
  ConsumerState<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<RecordPaymentSheet> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  DateTime _date = todayDate();
  String _method = kPaymentMethods.first;
  String? _proof;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount =
        TextEditingController(text: widget.view.charge.remaining.toString());
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseMoney(_amount.text);
    if (amount == null || amount <= 0) {
      snack(context, tr('Enter the amount received.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).addPayment(
            chargeId: widget.view.charge.id,
            amount: amount,
            date: _date,
            method: _method,
            proofPhoto: _proof,
            note: _note.text.trim(),
          );
      notifyChanged(ref);
      if (mounted) Navigator.of(context).pop();
    } on KostException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.view.charge.remaining;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Record payment'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(tr('Remaining balance: {amount}', {'amount': rp(remaining)})),
            const SizedBox(height: 16),
            moneyField(
              controller: _amount,
              label: tr('Amount received'),
              icon: Ph.money,
              helper: tr('Enter less than the balance for a partial payment'),
            ),
            DateField(
              label: tr('Payment date'),
              value: _date,
              onChanged: (d) {
                if (d != null) setState(() => _date = d);
              },
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final m in kPaymentMethods)
                  ChoiceChip(
                    label: Text(tr(m)),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                PhotoThumb(
                  name: _proof,
                  size: 56,
                  placeholderIcon: Ph.receipt,
                  onTap: _proof == null ? null : () => openPhoto(context, _proof!),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Ph.cameraPlus),
                  label: Text(_proof == null
                      ? tr('Add proof of transfer')
                      : tr('Replace photo')),
                  onPressed: () async {
                    final name = await pickPhotoSheet(context);
                    if (name != null) setState(() => _proof = name);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            appTextField(
              controller: _note,
              label: tr('Note (optional)'),
              icon: Ph.notePencil,
            ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(tr('Save payment')),
            ),
          ],
        ),
      ),
    );
  }
}
