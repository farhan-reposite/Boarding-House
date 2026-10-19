import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format.dart';
import '../../core/utils/launch.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../providers.dart';
import '../tenants/checkout_screen.dart';
import '../tenants/deposit_screen.dart';
import '../tenants/tenant_detail_screen.dart';
import '../tenants/tenant_form_screen.dart';
import 'room_form_screen.dart';
import '../../core/i18n/app_language.dart';

class RoomDetailScreen extends ConsumerWidget {
  const RoomDetailScreen({super.key, required this.roomId});
  final int roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomAsync = ref.watch(roomProvider(roomId));
    final tenantsAsync = ref.watch(roomTenantsProvider(roomId));
    final room = roomAsync.valueOrNull;

    if (room == null) {
      return Scaffold(
        appBar: AppBar(),
        body: roomAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const SizedBox.shrink(),
      );
    }
    final overviews = tenantsAsync.valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    final capacity = room.capacity < 1 ? 1 : room.capacity;
    final occupantCount = overviews?.length ?? 0;
    final hasVacancy = overviews != null && occupantCount < capacity;

    return Scaffold(
      appBar: AppBar(
        title: Text(room.name),
        actions: [
          IconButton(
            icon: const Icon(Ph.pencilSimple),
            tooltip: tr('Edit room'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RoomFormScreen(
                  room: room,
                  tenantCount: occupantCount,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Ph.trash),
            tooltip: tr('Delete room'),
            onPressed: () => _delete(context, ref, room),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _PhotoStrip(roomId: roomId),
          SectionCard(
            title: tr('Room'),
            trailing: RoomStatusPill(room.status),
            children: [
              InfoRow(tr('Price'), tr('{price} / month', {'price': rp(room.price)})),
              InfoRow(
                  tr('Capacity'),
                  tr(capacity == 1 ? '{n} / {max} tenant' : '{n} / {max} tenants',
                      {'n': occupantCount, 'max': capacity})),
              if (room.notes.isNotEmpty) InfoRow(tr('Notes'), room.notes),
              const SizedBox(height: 8),
              Text(tr('Facilities'),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              if (room.facilities.isEmpty)
                Text(tr('None listed'))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 0,
                  children: [
                    for (final f in room.facilities)
                      Chip(
                        label: Text(tr(f)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
            ],
          ),
          if (!tenantsAsync.hasValue)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            for (final overview in overviews!)
              _CurrentTenantCard(overview: overview),
            if (overviews.isEmpty)
              SectionCard(
                title: tr('Tenants'),
                children: [
                  Text(tr('No tenant in this room.')),
                  const SizedBox(height: 12),
                  if (room.status == RoomStatus.maintenance)
                    Text(
                      tr('This room is under maintenance. Set it to Available or Reserved (Edit room) before adding a tenant.'),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    )
                  else
                    FilledButton.icon(
                      icon: const Icon(Ph.userPlus),
                      label: Text(tr('Add tenant')),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TenantFormScreen(roomId: room.id),
                        ),
                      ),
                    ),
                ],
              )
            else if (hasVacancy)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: room.status == RoomStatus.maintenance
                    ? Text(
                        tr('This room is under maintenance. Set it to Available or Reserved (Edit room) before adding another tenant.'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      )
                    : OutlinedButton.icon(
                        icon: const Icon(Ph.userPlus),
                        label: Text(tr(
                            capacity - occupantCount == 1
                                ? '+ Add tenant ({n} more space)'
                                : '+ Add tenant ({n} more spaces)',
                            {'n': capacity - occupantCount})),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TenantFormScreen(roomId: room.id),
                          ),
                        ),
                      ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Room room) async {
    final ok = await confirmDialog(
      context,
      title: tr('Delete {name}?', {'name': room.name}),
      message:
          tr('The room and its photos will be removed. Records of past tenants and their payments are kept.'),
      confirmLabel: tr('Delete'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repoProvider).deleteRoom(room.id!);
      notifyChanged(ref);
      if (context.mounted) Navigator.of(context).pop();
    } on KostException catch (e) {
      if (context.mounted) snack(context, e.message);
    }
  }
}

// ------------------------------------------------------------------ photos

class _PhotoStrip extends ConsumerWidget {
  const _PhotoStrip({required this.roomId});
  final int roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(roomPhotosProvider(roomId)).valueOrNull ?? [];
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                InkWell(
                  onTap: () async {
                    final name = await pickPhotoSheet(context);
                    if (name == null) return;
                    await ref.read(repoProvider).addRoomPhoto(roomId, name);
                    notifyChanged(ref);
                  },
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Ph.cameraPlus),
                        SizedBox(height: 4),
                        Text(tr('Add photo')),
                      ],
                    ),
                  ),
                ),
                for (final photo in photos)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: GestureDetector(
                      onLongPress: () async {
                        final ok = await confirmDialog(
                          context,
                          title: tr('Delete photo?'),
                          message: tr('This photo will be removed from the room.'),
                          confirmLabel: tr('Delete'),
                          destructive: true,
                        );
                        if (!ok) return;
                        await ref.read(repoProvider).deleteRoomPhoto(photo);
                        notifyChanged(ref);
                      },
                      child: PhotoThumb(
                        name: photo.path,
                        size: 110,
                        onTap: () => openPhoto(context, photo.path),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                tr('Tap to view, long-press to delete'),
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- current tenant

class _CurrentTenantCard extends ConsumerWidget {
  const _CurrentTenantCard({required this.overview});
  final TenantOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = overview.tenant;
    final scheme = Theme.of(context).colorScheme;
    final held = ref.watch(depositHeldProvider(t.id!)).valueOrNull;
    final due = overview.nextDue;

    return SectionCard(
      title: tr('Tenant'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(t.name,
                  style: Theme.of(context).textTheme.titleLarge),
            ),
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
        InfoRow(tr('Phone'), t.phone),
        InfoRow(tr('School / work'), t.institution),
        InfoRow(tr('Home address'), t.homeAddress),
        const Divider(height: 24),
        InfoRow(tr('Stay'),
            '${fmtDate(t.moveInDate)} - ${t.endDate == null ? tr('no end date') : fmtDate(t.endDate)}'),
        InfoRow(tr('Rent'), tr('{price} / month', {'price': rp(t.rentAmount)})),
        InfoRow(
          tr('Next due'),
          due == null ? tr('None scheduled') : dueLabel(due),
          valueColor: (due != null && isOverdue(due)) ? scheme.error : null,
        ),
        if (overview.outstanding > 0)
          InfoRow(tr('Outstanding'), rp(overview.outstanding),
              valueColor: scheme.error),
        InfoRow(tr('Deposit held'), held == null ? '...' : rp(held)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Ph.user),
              label: Text(tr('Full details')),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TenantDetailScreen(tenantId: t.id!),
                ),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Ph.piggyBank),
              label: Text(tr('Deposit history')),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DepositScreen(tenantId: t.id!),
                ),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Ph.signOut),
              label: Text(tr('Check out')),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CheckoutScreen(tenantId: t.id!),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
