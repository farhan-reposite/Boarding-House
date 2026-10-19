import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/repository.dart';
import '../../providers.dart';
import '../../core/i18n/app_language.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.tenantId});
  final int tenantId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _deduction = TextEditingController();
  final _reason = TextEditingController();
  DateTime _date = todayDate();
  bool _busy = false;

  @override
  void dispose() {
    _deduction.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm(String name, int held) async {
    final deduction = parseMoney(_deduction.text) ?? 0;
    if (deduction > held) {
      snack(context, tr('Deduction is more than the deposit held.'));
      return;
    }
    final refund = held - deduction;
    final ok = await confirmDialog(
      context,
      title: tr('Check out {name}?', {'name': name}),
      message: refund > 0
          ? tr('The room becomes available and the deposit refund of {amount} is recorded as handed back.',
              {'amount': rp(refund)})
          : tr('The room becomes available.'),
      confirmLabel: tr('Check out'),
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).checkoutTenant(
            tenantId: widget.tenantId,
            moveOut: _date,
            deduction: deduction,
            deductionNote: _reason.text.trim(),
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
    final overviewAsync = ref.watch(tenantOverviewProvider(widget.tenantId));
    final heldAsync = ref.watch(depositHeldProvider(widget.tenantId));
    final overview = overviewAsync.valueOrNull;
    final held = heldAsync.valueOrNull;

    if (overview == null || held == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Check out'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final t = overview.tenant;
    final scheme = Theme.of(context).colorScheme;
    final deduction = parseMoney(_deduction.text) ?? 0;
    final tooMuch = deduction > held;
    final refund = tooMuch ? 0 : held - deduction;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Check out'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.name, style: Theme.of(context).textTheme.titleLarge),
          Text(tr('Room {name}', {'name': t.roomName}),
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          DateField(
            label: tr('Move-out date'),
            value: _date,
            firstDate: t.moveInDate,
            onChanged: (d) {
              if (d != null) setState(() => _date = d);
            },
          ),
          const SizedBox(height: 4),
          Text(tr('Deposit settlement'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          InfoRow(tr('Deposit held'), rp(held)),
          InfoRow(
            tr('Unpaid rent'),
            rp(overview.outstanding),
            valueColor: overview.outstanding > 0 ? scheme.error : null,
          ),
          if (overview.outstanding > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                tr('Unpaid rent is not deducted automatically. Enter it below as a deduction if you want to keep it from the deposit; invoices stay on the payments list.'),
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          const SizedBox(height: 8),
          moneyField(
            controller: _deduction,
            label: tr('Deduction (optional)'),
            icon: Ph.minusCircle,
            onChanged: (_) => setState(() {}),
            errorText: tooMuch ? tr('More than the deposit held') : null,
          ),
          appTextField(
            controller: _reason,
            label: tr('Reason for deduction'),
            icon: Ph.fileText,
            helper: tr('e.g. unpaid rent, broken window'),
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(child: Text(tr('Refund to tenant'))),
              Text(
                rp(refund),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Ph.signOut),
            label: Text(tr('Confirm check-out')),
            onPressed: (_busy || tooMuch) ? null : () => _confirm(t.name, held),
          ),
        ],
      ),
    );
  }
}
