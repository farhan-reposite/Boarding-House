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

class RoomFormScreen extends ConsumerStatefulWidget {
  const RoomFormScreen({super.key, this.room, this.tenantCount = 0});

  /// null = add a new room.
  final Room? room;

  /// How many active tenants currently live in this room. An occupied
  /// room's status is controlled by check-in / check-out, and capacity
  /// can't be set below this number.
  final int tenantCount;

  @override
  ConsumerState<RoomFormScreen> createState() => _RoomFormScreenState();
}

class _RoomFormScreenState extends ConsumerState<RoomFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _capacity = TextEditingController();
  final _notes = TextEditingController();
  final _custom = TextEditingController();
  final List<String> _facilities = [];
  RoomStatus _status = RoomStatus.available;
  bool _saving = false;

  bool get _editing => widget.room != null;
  bool get _hasTenant => widget.tenantCount > 0;

  @override
  void initState() {
    super.initState();
    final r = widget.room;
    if (r != null) {
      _name.text = r.name;
      _price.text = r.price.toString();
      _capacity.text = r.capacity.toString();
      _notes.text = r.notes;
      _facilities.addAll(r.facilities);
      _status = r.status;
      if (!_hasTenant && _status == RoomStatus.occupied) {
        _status = RoomStatus.available;
      }
    } else {
      _capacity.text = '1';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _capacity.dispose();
    _notes.dispose();
    _custom.dispose();
    super.dispose();
  }

  void _addCustom() {
    final text = _custom.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!_facilities.contains(text)) _facilities.add(text);
      _custom.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(repoProvider);
    final capacity = int.tryParse(_capacity.text.trim()) ?? 1;
    final room = Room(
      id: widget.room?.id,
      name: _name.text.trim(),
      price: parseMoney(_price.text) ?? 0,
      status: _hasTenant ? widget.room!.status : _status,
      capacity: capacity,
      facilities: List<String>.from(_facilities),
      notes: _notes.text.trim(),
    );
    try {
      if (_editing) {
        await repo.updateRoom(room);
      } else {
        await repo.insertRoom(room);
      }
      notifyChanged(ref);
      if (mounted) Navigator.of(context).pop();
    } on KostException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        snack(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <String>[
      ...kFacilityPresets,
      ..._facilities.where((f) => !kFacilityPresets.contains(f)),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? tr('Edit room') : tr('Add room'))),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TutorialTarget(id: 'roomForm.name', child: appTextField(
              controller: _name,
              label: tr('Room name / number'),
              icon: Ph.doorOpen,
              capitalization: TextCapitalization.characters,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? tr('Enter a room name') : null,
            )),
            TutorialTarget(id: 'roomForm.price', child: moneyField(
              controller: _price,
              label: tr('Price per month'),
              icon: Ph.tagSimple,
              validator: (v) {
                final n = parseMoney(v ?? '');
                return (n == null || n <= 0) ? tr('Enter the monthly price') : null;
              },
            )),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _capacity,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: tr('Room capacity (number of tenants)'),
                  prefixIcon: const Icon(Ph.usersThree),
                  helperText: _hasTenant
                      ? tr(
                          widget.tenantCount == 1
                              ? '{n} tenant currently in this room'
                              : '{n} tenants currently in this room',
                          {'n': widget.tenantCount})
                      : tr('How many tenants can share this room'),
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 1) return tr('Enter at least 1');
                  if (n < widget.tenantCount) {
                    return tr(
                      widget.tenantCount == 1
                          ? 'Can\'t be less than the {n} tenant already here'
                          : 'Can\'t be less than the {n} tenants already here',
                      {'n': widget.tenantCount});
                  }
                  return null;
                },
              ),
            ),
            Text(tr('Status'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_hasTenant)
              Text(
                _status == RoomStatus.occupied
                    ? tr('Occupied - this room is full. The status changes automatically as tenants check in or out.')
                    : tr('Partially occupied - this room still has space. The status changes automatically as tenants check in or out.'),
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final s in [
                    RoomStatus.available,
                    RoomStatus.reserved,
                    RoomStatus.maintenance,
                  ])
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            Text(tr('Facilities'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final f in options)
                  FilterChip(
                    label: Text(tr(f)),
                    selected: _facilities.contains(f),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _facilities.add(f);
                      } else {
                        _facilities.remove(f);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _custom,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: tr('Other facility'),
                      prefixIcon: Icon(Ph.plusCircle),
                    ),
                    onSubmitted: (_) => _addCustom(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addCustom,
                  icon: const Icon(Ph.plus),
                  tooltip: tr('Add facility'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            appTextField(
              controller: _notes,
              label: tr('Notes (optional)'),
              icon: Ph.notePencil,
              maxLines: 3,
            ),
            if (!_editing)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  tr('You can add photos after saving, from the room details page.'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            TutorialTarget(
              id: 'roomForm.save',
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_editing ? tr('Save changes') : tr('Add room')),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
