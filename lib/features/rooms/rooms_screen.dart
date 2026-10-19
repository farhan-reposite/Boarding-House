import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/kost_logo.dart';
import '../../data/models.dart';
import '../../providers.dart';
import 'room_detail_screen.dart';
import 'room_form_screen.dart';
import 'room_matrix.dart';
import 'room_setup_wizard.dart';
import '../../core/i18n/app_language.dart';
import '../../core/tutorial/tutorial_target.dart';

enum _RoomFilter {
  all('All'),
  attention('Needs attention'),
  vacant('Vacant'),
  occupied('Occupied'),
  maintenance('Maintenance');

  const _RoomFilter(this._key);
  final String _key;
  String get label => tr(_key);

  bool matches(RoomOverview o) => switch (this) {
        _RoomFilter.all => true,
        _RoomFilter.attention => roomHealth(o).needsAttention,
        _RoomFilter.vacant =>
          o.tenants.isEmpty && o.room.status != RoomStatus.maintenance,
        _RoomFilter.occupied => o.tenants.isNotEmpty,
        _RoomFilter.maintenance => o.room.status == RoomStatus.maintenance,
      };
}

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  _RoomFilter _filter = _RoomFilter.all;
  bool _grid = true;

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomOverviewsProvider);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: const Padding(
          padding: EdgeInsets.all(12),
          child: KostLogo(size: 28),
        ),
        title: Text(tr('Rooms')),
        actions: [
          IconButton(
            tooltip: _grid ? tr('Show as list') : tr('Show as grid'),
            icon: Icon(_grid ? Ph.listBullets : Ph.squaresFour),
            onPressed: () => setState(() => _grid = !_grid),
          ),
          TutorialTarget(
            id: 'rooms.quickSetup',
            child: IconButton(
              tooltip: tr('Quick setup: add many rooms'),
              icon: const Icon(Ph.magicWand),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RoomSetupWizard()),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: TutorialTarget(
        id: 'rooms.add',
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const RoomFormScreen())),
          icon: const Icon(Ph.plus),
          label: Text(tr('Add room')),
        ),
      ),
      body: rooms.ui(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Ph.buildings,
                        size: 64, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(tr('Set up your building'),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      tr('Generate all your rooms in one go, with names and prices, in under two minutes.'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RoomSetupWizard()),
                      ),
                      icon: const Icon(Ph.magicWand),
                      label: Text(tr('Quick setup')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RoomFormScreen()),
                      ),
                      child: Text(tr('Add a single room')),
                    ),
                  ],
                ),
              ),
            );
          }
          final shown = list.where(_filter.matches).toList();

          return Column(
            children: [
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    for (final f in _RoomFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                              '${f.label} (${list.where(f.matches).length})'),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              if (_grid)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                      alignment: Alignment.centerLeft, child: RoomLegend()),
                ),
              Expanded(
                child: shown.isEmpty
                    ? EmptyState(
                        icon: Ph.funnelX,
                        message: tr('No rooms match this filter.'),
                      )
                    : _grid
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            child: RoomMatrix(rooms: shown),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: shown.length,
                            itemBuilder: (_, i) =>
                                _RoomCard(overview: shown[i]),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.overview});
  final RoomOverview overview;

  @override
  Widget build(BuildContext context) {
    final room = overview.room;
    final tenants = overview.tenants;
    final due = overview.nextDue;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RoomDetailScreen(roomId: room.id!)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              PhotoThumb(
                name: overview.coverPhoto,
                size: 76,
                placeholderIcon: Ph.bed,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        RoomStatusPill(room.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(tr('{price} / month', {'price': rp(room.price)})),
                    if (tenants.isNotEmpty)
                      Text(
                        room.capacity > 1
                            ? '${tenants.map((t) => t.name).join(', ')} (${tenants.length}/${room.capacity})'
                            : tenants.first.name,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (tenants.isNotEmpty && due != null)
                      Text(
                        dueLabel(due),
                        style: TextStyle(
                          fontSize: 12,
                          color: isOverdue(due)
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
