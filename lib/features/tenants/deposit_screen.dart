import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../providers.dart';
import '../../core/i18n/app_language.dart';

class DepositScreen extends ConsumerWidget {
  const DepositScreen({super.key, required this.tenantId});
  final int tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(depositsProvider(tenantId));
    final held = ref.watch(depositHeldProvider(tenantId)).valueOrNull;
    final tenant = ref.watch(tenantOverviewProvider(tenantId)).valueOrNull;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tenant == null
            ? tr('Deposit')
            : tr('Deposit - {name}', {'name': tenant.tenant.name})),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _DepositEntrySheet(tenantId: tenantId),
        ),
        icon: const Icon(Ph.plus),
        label: Text(tr('Add entry')),
      ),
      body: entries.ui(data: (list) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(child: Text(tr('Deposit currently held'))),
                    Text(
                      held == null ? '...' : rp(held),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            if (list.isEmpty)
              Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text(tr('No deposit entries yet.'))),
              ),
            for (final e in list)
              ListTile(
                leading: Icon(
                  e.type == DepositType.received
                      ? Ph.arrowDownLeft
                      : (e.type == DepositType.refund
                          ? Ph.arrowUUpLeft
                          : Ph.minusCircle),
                  color: e.type == DepositType.received
                      ? const Color(0xFF17703A)
                      : scheme.error,
                ),
                title: Text(e.type.label),
                subtitle: Text(
                  '${fmtDate(e.date)}${e.note.isEmpty ? '' : '\n${e.note}'}',
                ),
                isThreeLine: e.note.isNotEmpty,
                trailing: Text(
                  '${e.type == DepositType.received ? '+' : '-'}${rp(e.amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: e.type == DepositType.received
                        ? const Color(0xFF17703A)
                        : scheme.error,
                  ),
                ),
                onLongPress: () async {
                  final ok = await confirmDialog(
                    context,
                    title: tr('Delete this entry?'),
                    message:
                        tr('Use this only to fix a mistake. The held amount will be recalculated.'),
                    confirmLabel: tr('Delete'),
                    destructive: true,
                  );
                  if (!ok) return;
                  await ref.read(repoProvider).deleteDeposit(e.id);
                  notifyChanged(ref);
                },
              ),
            if (list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  tr('Long-press an entry to delete it (for fixing mistakes).'),
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _DepositEntrySheet extends ConsumerStatefulWidget {
  const _DepositEntrySheet({required this.tenantId});
  final int tenantId;

  @override
  ConsumerState<_DepositEntrySheet> createState() => _DepositEntrySheetState();
}

class _DepositEntrySheetState extends ConsumerState<_DepositEntrySheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DepositType _type = DepositType.received;
  DateTime _date = todayDate();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseMoney(_amount.text);
    if (amount == null || amount <= 0) {
      snack(context, tr('Enter an amount.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).addDeposit(
            tenantId: widget.tenantId,
            type: _type,
            amount: amount,
            date: _date,
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Add deposit entry'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final t in DepositType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            moneyField(
              controller: _amount,
              label: tr('Amount'),
              icon: Ph.money,
            ),
            DateField(
              label: tr('Date'),
              value: _date,
              onChanged: (d) {
                if (d != null) setState(() => _date = d);
              },
            ),
            appTextField(
              controller: _note,
              label: tr('Note (optional)'),
              icon: Ph.notePencil,
            ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
  }
}
