import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/kost_logo.dart';
import '../../data/models.dart';
import '../../providers.dart';
import 'tenant_detail_screen.dart';
import 'tenant_form_screen.dart';
import '../../core/i18n/app_language.dart';
import '../../core/tutorial/tutorial_target.dart';

class TenantsScreen extends ConsumerWidget {
  const TenantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenants = ref.watch(tenantOverviewsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 56,
          leading: const Padding(
            padding: EdgeInsets.all(12),
            child: KostLogo(size: 28),
          ),
          title: Text(tr('Tenants')),
          bottom: TabBar(
            tabs: [
              Tab(text: tr('Active')),
              Tab(text: tr('Former')),
            ],
          ),
        ),
        floatingActionButton: TutorialTarget(
          id: 'tenants.add',
          child: FloatingActionButton.extended(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TenantFormScreen())),
            icon: const Icon(Ph.userPlus),
            label: Text(tr('Add tenant')),
          ),
        ),
        body: tenants.ui(
          data: (all) {
            final active = all.where((o) => o.tenant.isActive).toList();
            final former = all.where((o) => !o.tenant.isActive).toList();
            return TabBarView(
              children: [
                _TenantList(
                  items: active,
                  emptyMessage:
                      tr('No active tenants.\nTap "Add tenant" to check someone in.'),
                ),
                _TenantList(
                  items: former,
                  emptyMessage: tr('No former tenants yet.'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TenantList extends StatelessWidget {
  const _TenantList({required this.items, required this.emptyMessage});
  final List<TenantOverview> items;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(icon: Ph.users, message: emptyMessage);
    }
    final scheme = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final o = items[i];
        final t = o.tenant;
        final due = o.nextDue;
        final lines = <String>[
          [
            if (t.roomName.isNotEmpty) t.roomName,
            if (t.phone.isNotEmpty) t.phone,
          ].join(' · '),
          if (!t.isActive) tr('Moved out {date}', {'date': fmtDate(t.moveOutDate)}),
        ];
        final overdue = t.isActive && (o.overdueCount > 0);
        // Each tenant sits in its own card, like the room and payment lists.
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            child: Text(t.name.isEmpty ? '?' : t.name[0].toUpperCase()),
          ),
          title: Text(t.name,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in lines.where((l) => l.isNotEmpty)) Text(l),
              if (t.isActive && due != null)
                Text(
                  dueLabel(due),
                  style: TextStyle(
                    fontSize: 12,
                    color: isOverdue(due) ? scheme.error : scheme.outline,
                  ),
                ),
            ],
          ),
          trailing: overdue
              ? const PaymentStatusPill(PaymentStatus.overdue)
              : (!t.isActive && o.outstanding > 0)
              ? Text(rp(o.outstanding), style: TextStyle(color: scheme.error))
              : null,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TenantDetailScreen(tenantId: t.id!),
            ),
          ),
          ),
        );
      },
    );
  }
}
