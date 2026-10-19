import 'package:flutter/material.dart';

import '../../core/utils/date_helpers.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import 'room_detail_screen.dart';
import '../../core/i18n/app_language.dart';

/// How a room is doing at a glance: a tone (color) and a short label.
class RoomHealth {
  const RoomHealth(this.tone, this.label);
  final Tone tone;
  final String label;

  bool get needsAttention => tone == Tone.danger || tone == Tone.warning;
}

/// How many days before a lease end date a room is flagged amber.
const int kLeaseWarningDays = 30;

RoomHealth roomHealth(RoomOverview o) {
  final today = todayDate();
  final room = o.room;
  if (room.status == RoomStatus.maintenance) {
    return RoomHealth(Tone.warning, tr('Maintenance'));
  }
  if (o.tenants.isNotEmpty) {
    final due = o.nextDue;
    if (due != null && due.isBefore(today)) {
      final days = today.difference(due).inDays;
      return RoomHealth(Tone.danger, tr('Overdue {n}d', {'n': days}));
    }
    DateTime? ends;
    for (final t in o.tenants) {
      final e = t.endDate;
      if (e != null && (ends == null || e.isBefore(ends))) ends = e;
    }
    if (ends != null) {
      final left = ends.difference(today).inDays;
      if (left >= 0 && left <= kLeaseWarningDays) {
        return RoomHealth(Tone.warning, tr('Ends in {n}d', {'n': left}));
      }
    }
    return RoomHealth(Tone.success, tr('Occupied'));
  }
  if (room.status == RoomStatus.reserved) {
    return RoomHealth(Tone.info, tr('Reserved'));
  }
  return RoomHealth(Tone.info, tr('Vacant'));
}

class RoomTile extends StatelessWidget {
  const RoomTile({super.key, required this.overview, this.compact = false});
  final RoomOverview overview;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final health = roomHealth(overview);
    final colors = toneColors(context, health.tone);
    final accent = toneAccent(health.tone);
    final tenants = overview.tenants;
    final who = tenants.isEmpty
        ? ''
        : tenants.length == 1
            ? tenants.first.name
            : '${tenants.first.name} +${tenants.length - 1}';

    return Material(
      color: colors.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => RoomDetailScreen(roomId: overview.room.id!)),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      overview.room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 15 : 18,
                        fontWeight: FontWeight.w800,
                        color: colors.fg,
                      ),
                    ),
                  ),
                  Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                ],
              ),
              const Spacer(),
              if (!compact && who.isNotEmpty)
                Text(
                  who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.fg),
                ),
              Text(
                health.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10.5 : 12,
                  fontWeight: FontWeight.w700,
                  color: colors.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A non-scrolling grid of room tiles, for embedding in other screens.
class RoomMatrix extends StatelessWidget {
  const RoomMatrix({super.key, required this.rooms, this.compact = false});
  final List<RoomOverview> rooms;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: compact ? 104 : 150,
        mainAxisExtent: compact ? 66 : 92,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: rooms.length,
      itemBuilder: (_, i) => RoomTile(overview: rooms[i], compact: compact),
    );
  }
}

class RoomLegend extends StatelessWidget {
  const RoomLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    Widget item(Tone t, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: toneAccent(t), shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label, style: style),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        item(Tone.success, tr('Occupied')),
        item(Tone.info, tr('Vacant')),
        item(Tone.warning, tr('Ending / maintenance')),
        item(Tone.danger, tr('Overdue')),
      ],
    );
  }
}
