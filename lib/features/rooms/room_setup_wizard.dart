import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../providers.dart';
import '../../core/i18n/app_language.dart';
import '../../core/tutorial/tutorial_target.dart';

enum _Naming { byFloor, sequential }

/// One-screen wizard that generates every room of a building at once, with
/// names and prices, and shows a live preview before anything is saved.
class RoomSetupWizard extends ConsumerStatefulWidget {
  const RoomSetupWizard({super.key});

  @override
  ConsumerState<RoomSetupWizard> createState() => _RoomSetupWizardState();
}

class _RoomSetupWizardState extends ConsumerState<RoomSetupWizard> {
  static const _maxRooms = 200;

  final _floors = TextEditingController(text: '2');
  final _perFloor = TextEditingController(text: '6');
  final _prefix = TextEditingController();
  final _price = TextEditingController();
  final _step = TextEditingController();
  final _capacity = TextEditingController(text: '1');
  final Set<String> _facilities = {'Bed', 'Wardrobe', 'Fan'};
  _Naming _naming = _Naming.byFloor;
  bool _saving = false;

  @override
  void dispose() {
    _floors.dispose();
    _perFloor.dispose();
    _prefix.dispose();
    _price.dispose();
    _step.dispose();
    _capacity.dispose();
    super.dispose();
  }

  int get _floorCount => (int.tryParse(_floors.text) ?? 0).clamp(0, 50).toInt();
  int get _perFloorCount => (int.tryParse(_perFloor.text) ?? 0).clamp(0, 99).toInt();

  List<Room> _generate() {
    final floors = _floorCount;
    final per = _perFloorCount;
    if (floors == 0 || per == 0) return [];
    final base = parseMoney(_price.text) ?? 0;
    final step = parseMoney(_step.text) ?? 0;
    final capacity = (int.tryParse(_capacity.text) ?? 1).clamp(1, 20).toInt();
    final prefix = _prefix.text.trim().toUpperCase();
    final rooms = <Room>[];
    var counter = 0;
    for (var f = 1; f <= floors; f++) {
      for (var i = 1; i <= per; i++) {
        counter++;
        if (rooms.length >= _maxRooms) break;
        final name = _naming == _Naming.byFloor
            ? '$prefix${f * 100 + i}'
            : '$prefix$counter';
        rooms.add(Room(
          name: name,
          price: base + step * (f - 1),
          status: RoomStatus.available,
          capacity: capacity,
          facilities: _facilities.toList(),
        ));
      }
    }
    return rooms;
  }

  Future<void> _create(List<Room> rooms) async {
    setState(() => _saving = true);
    final repo = ref.read(repoProvider);
    var created = 0;
    var skipped = 0;
    for (final r in rooms) {
      try {
        await repo.insertRoom(r);
        created++;
      } on KostException {
        skipped++; // a room with that name already exists
      }
    }
    notifyChanged(ref);
    if (!mounted) return;
    Navigator.of(context).pop();
    snack(
        context,
        skipped == 0
            ? tr('Created {n} rooms.', {'n': created})
            : tr('Created {n} rooms, skipped {skipped} that already exist.',
                {'n': created, 'skipped': skipped}));
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _generate();
    final priceOk = (parseMoney(_price.text) ?? 0) > 0;
    final scheme = Theme.of(context).colorScheme;
    final options = [...kFacilityPresets];

    return Scaffold(
      appBar: AppBar(title: Text(tr('Quick property setup'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TutorialTarget(
            id: 'wizard.create',
            child: FilledButton.icon(
              onPressed: (!_saving && rooms.isNotEmpty && priceOk)
                  ? () => _create(rooms)
                  : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Ph.check),
              label: Text(rooms.isEmpty
                  ? tr('Create rooms')
                  : tr('Create {n} rooms', {'n': rooms.length})),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('1. Layout'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TutorialTarget(
            id: 'wizard.layout',
            child: Row(
              children: [
                Expanded(
                  child: _numberField(_floors, tr('Floors'), Ph.stack),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _numberField(
                      _perFloor, tr('Rooms per floor'), Ph.door),
                ),
              ],
            ),
          ),
          SegmentedButton<_Naming>(
            segments: [
              ButtonSegment(
                  value: _Naming.byFloor, label: Text(tr('By floor: 101, 102, 201'))),
              ButtonSegment(
                  value: _Naming.sequential, label: Text(tr('Sequential: 1, 2, 3'))),
            ],
            selected: {_naming},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _naming = s.first),
          ),
          const SizedBox(height: 12),
          appTextField(
            controller: _prefix,
            label: tr('Name prefix (optional)'),
            icon: Ph.tag,
            capitalization: TextCapitalization.characters,
            helper: tr('e.g. "A" gives A101, A102 …'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(tr('2. Pricing'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TutorialTarget(
            id: 'wizard.price',
            child: moneyField(
              controller: _price,
              label: tr('Standard price per month'),
              icon: Ph.tagSimple,
              onChanged: (_) => setState(() {}),
            ),
          ),
          moneyField(
            controller: _step,
            label: tr('Extra per floor above the first (optional)'),
            icon: Ph.trendUp,
            helper: tr('Floor 2 costs this much more than floor 1, floor 3 twice as much …'),
            onChanged: (_) => setState(() {}),
          ),
          _numberField(_capacity, tr('Tenants per room'), Ph.usersThree),
          const SizedBox(height: 4),
          Text(tr('3. Standard facilities'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in options)
                FilterChip(
                  label: Text(tr(f)),
                  selected: _facilities.contains(f),
                  onSelected: (v) => setState(() {
                    v ? _facilities.add(f) : _facilities.remove(f);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(tr('Preview'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (rooms.isEmpty)
            Text(tr('Enter floors and rooms per floor.'),
                style: TextStyle(color: scheme.onSurfaceVariant))
          else ...[
            if (!priceOk)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr('Enter a standard price to continue.'),
                    style: TextStyle(color: scheme.error)),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in rooms)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: toneColors(context, Tone.info).bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      priceOk ? '${r.name} · ${rp(r.price)}' : r.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: toneColors(context, Tone.info).fg,
                      ),
                    ),
                  ),
              ],
            ),
            if (_floorCount * _perFloorCount > _maxRooms)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr('Limited to {n} rooms at a time.', {'n': _maxRooms}),
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _numberField(TextEditingController c, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }
}
