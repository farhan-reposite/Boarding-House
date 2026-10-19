import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format.dart';
import '../../core/utils/launch.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../providers.dart';
import '../payments/payments_screen.dart';
import 'checkout_screen.dart';
import 'deposit_screen.dart';
import 'tenant_form_screen.dart';
import '../../core/i18n/app_language.dart';

class TenantDetailScreen extends ConsumerWidget {
  const TenantDetailScreen({super.key, required this.tenantId});
  final int tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tenantOverviewProvider(tenantId));
    final overview = async.valueOrNull;

    if (overview == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const SizedBox.shrink(),
      );
    }

    final t = overview.tenant;
    final scheme = Theme.of(context).colorScheme;
    final held = ref.watch(depositHeldProvider(tenantId)).valueOrNull;
    final charges = ref.watch(chargesProvider(tenantId)).valueOrNull ?? [];
    final due = overview.nextDue;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TenantFormScreen(tenant: t)));
                case 'checkout':
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CheckoutScreen(tenantId: tenantId)));
                case 'delete':
                  await _delete(context, ref, t);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(tr('Edit details'))),
              if (t.isActive)
                PopupMenuItem(value: 'checkout', child: Text(tr('Check out'))),
              if (!t.isActive)
                PopupMenuItem(
                    value: 'delete', child: Text(tr('Delete record'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SectionCard(
            title: t.name,
            trailing: Pill(
              label: t.isActive ? tr('Active') : tr('Moved out'),
              colors: toneColors(
                  context, t.isActive ? Tone.success : Tone.neutral),
            ),
            children: [
              InfoRow(tr('Room'), t.roomName),
              Row(
                children: [
                  Expanded(child: InfoRow(tr('Phone'), t.phone)),
                  IconButton(
                    icon: const Icon(Ph.phoneCall),
                    tooltip: tr('Call'),
                    onPressed: () => callNumber(context, t.phone),
                  ),
                  IconButton(
                    icon: const Icon(Ph.chatCircleText),
                    tooltip: tr('WhatsApp'),
                    onPressed: () => openWhatsApp(context, t.phone),
                  ),
                ],
              ),
            ],
          ),
          SectionCard(
            title: tr('Personal details'),
            children: [
              InfoRow(tr('ID number'), t.idNumber),
              InfoRow(tr('School / work'), t.institution),
              InfoRow(tr('School / work address'), t.institutionAddress),
              InfoRow(tr('Home address'), t.homeAddress),
              if (t.idPhoto != null) ...[
                const SizedBox(height: 8),
                Text(tr('ID photo'),
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                PhotoThumb(
                  name: t.idPhoto,
                  size: 120,
                  onTap: () => openPhoto(context, t.idPhoto!),
                ),
              ],
              if (t.notes.isNotEmpty) InfoRow(tr('Notes'), t.notes),
            ],
          ),
          SectionCard(
            title: tr('Emergency contact'),
            trailing: t.emergencyPhone.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Ph.phoneCall),
                    tooltip: tr('Call emergency contact'),
                    onPressed: () => callNumber(context, t.emergencyPhone),
                  ),
            children: [
              InfoRow(tr('Name'), t.emergencyName),
              InfoRow(tr('Relationship'), t.emergencyRelation),
              InfoRow(tr('Phone'), t.emergencyPhone),
              InfoRow(tr('Address'), t.emergencyAddress),
            ],
          ),
          SectionCard(
            title: tr('Stay'),
            children: [
              InfoRow(tr('Move-in'), fmtDate(t.moveInDate)),
              InfoRow(tr('End date'), t.endDate == null ? tr('Not set') : fmtDate(t.endDate)),
              if (!t.isActive) InfoRow(tr('Moved out'), fmtDate(t.moveOutDate)),
              InfoRow(tr('Rent'), tr('{price} / month', {'price': rp(t.rentAmount)})),
              if (t.isActive)
                InfoRow(
                  tr('Next due'),
                  due == null ? tr('None scheduled') : dueLabel(due),
                  valueColor:
                      (due != null && isOverdue(due)) ? scheme.error : null,
                ),
              if (overview.outstanding > 0)
                InfoRow(tr('Outstanding'), rp(overview.outstanding),
                    valueColor: scheme.error),
            ],
          ),
          SectionCard(
            title: tr('Deposit'),
            trailing: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DepositScreen(tenantId: tenantId))),
              child: Text(tr('History')),
            ),
            children: [
              InfoRow(tr('Held'), held == null ? '...' : rp(held)),
            ],
          ),
          SectionCard(
            title: tr('Rent payments'),
            children: [
              if (charges.isEmpty)
                Text(tr('No invoices yet.'))
              else
                for (final v in charges)
                  ChargeTile(view: v, showTenant: false),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Tenant t) async {
    final ok = await confirmDialog(
      context,
      title: tr('Delete {name}?', {'name': t.name}),
      message:
          tr('This permanently removes the tenant together with all their invoices, payments and deposit records. This cannot be undone.'),
      confirmLabel: tr('Delete'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repoProvider).deleteTenant(t.id!);
      notifyChanged(ref);
      if (context.mounted) Navigator.of(context).pop();
    } on KostException catch (e) {
      if (context.mounted) snack(context, e.message);
    }
  }
}
