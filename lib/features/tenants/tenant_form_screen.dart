import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../core/utils/photo_store.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../providers.dart';
import '../../core/i18n/app_language.dart';
import '../../core/tutorial/tutorial_target.dart';

class TenantFormScreen extends ConsumerStatefulWidget {
  const TenantFormScreen({super.key, this.tenant, this.roomId});

  /// null = add a new tenant (check-in).
  final Tenant? tenant;

  /// Pre-selected room when adding from a room's detail page.
  final int? roomId;

  @override
  ConsumerState<TenantFormScreen> createState() => _TenantFormScreenState();
}

class _TenantFormScreenState extends ConsumerState<TenantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _idNumber = TextEditingController();
  final _institution = TextEditingController();
  final _institutionAddress = TextEditingController();
  final _homeAddress = TextEditingController();
  final _emName = TextEditingController();
  final _emRelation = TextEditingController();
  final _emPhone = TextEditingController();
  final _emAddress = TextEditingController();
  final _rent = TextEditingController();
  final _deposit = TextEditingController();
  final _notes = TextEditingController();

  String? _idPhoto;
  String? _originalIdPhoto;
  int? _roomId;
  DateTime _moveIn = todayDate();
  DateTime? _endDate;
  bool _billFromCurrent = true;
  bool _rentTouched = false;
  bool _saving = false;
  List<Room> _eligibleRooms = [];
  bool _roomsLoaded = false;

  bool get _editing => widget.tenant != null;

  @override
  void initState() {
    super.initState();
    final t = widget.tenant;
    if (t != null) {
      _name.text = t.name;
      _phone.text = t.phone;
      _idNumber.text = t.idNumber;
      _institution.text = t.institution;
      _institutionAddress.text = t.institutionAddress;
      _homeAddress.text = t.homeAddress;
      _emName.text = t.emergencyName;
      _emRelation.text = t.emergencyRelation;
      _emPhone.text = t.emergencyPhone;
      _emAddress.text = t.emergencyAddress;
      _rent.text = t.rentAmount.toString();
      _notes.text = t.notes;
      _idPhoto = t.idPhoto;
      _originalIdPhoto = t.idPhoto;
      _roomId = t.roomId;
      _moveIn = t.moveInDate;
      _endDate = t.endDate;
      _rentTouched = true;
    } else {
      _roomId = widget.roomId;
      _loadRooms();
    }
  }

  Future<void> _loadRooms() async {
    final rooms = await ref.read(repoProvider).getRooms();
    if (!mounted) return;
    final eligible = rooms
        .where((r) =>
            r.status == RoomStatus.available || r.status == RoomStatus.reserved)
        .toList();
    setState(() {
      _eligibleRooms = eligible;
      _roomsLoaded = true;
    });
    if (_roomId != null) {
      final match = eligible.where((r) => r.id == _roomId).firstOrNull;
      if (match != null) {
        _selectRoom(match);
      } else {
        setState(() => _roomId = null);
      }
    }
  }

  void _selectRoom(Room room) {
    setState(() {
      _roomId = room.id;
      if (!_rentTouched) _rent.text = room.price.toString();
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _idNumber,
      _institution,
      _institutionAddress,
      _homeAddress,
      _emName,
      _emRelation,
      _emPhone,
      _emAddress,
      _rent,
      _deposit,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickIdPhoto() async {
    final name = await pickPhotoSheet(context);
    if (name == null) return;
    // A photo picked in this session but not saved is replaced right away.
    if (_idPhoto != null && _idPhoto != _originalIdPhoto) {
      await PhotoStore.delete(_idPhoto);
    }
    setState(() => _idPhoto = name);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_editing && _roomId == null) {
      snack(context, tr('Select a room for this tenant.'));
      return;
    }
    if (_endDate != null && !_endDate!.isAfter(_moveIn)) {
      snack(context, tr('End date must be after the move-in date.'));
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(repoProvider);
    final old = widget.tenant;
    final rent = parseMoney(_rent.text) ?? 0;

    final latest = latestDueOnOrBefore(_moveIn, todayDate());
    final billingStart =
        (!_editing && _billFromCurrent && latest.isAfter(_moveIn))
            ? latest
            : _moveIn;

    final tenant = Tenant(
      id: old?.id,
      roomId: _roomId,
      roomName: old?.roomName ?? '',
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      idNumber: _idNumber.text.trim(),
      idPhoto: _idPhoto,
      institution: _institution.text.trim(),
      institutionAddress: _institutionAddress.text.trim(),
      homeAddress: _homeAddress.text.trim(),
      emergencyName: _emName.text.trim(),
      emergencyRelation: _emRelation.text.trim(),
      emergencyPhone: _emPhone.text.trim(),
      emergencyAddress: _emAddress.text.trim(),
      rentAmount: rent,
      moveInDate: old?.moveInDate ?? _moveIn,
      billingStart: old?.billingStart ?? billingStart,
      endDate: _endDate,
      moveOutDate: old?.moveOutDate,
      isActive: old?.isActive ?? true,
      notes: _notes.text.trim(),
    );

    try {
      if (_editing) {
        await repo.updateTenant(tenant);
        if (_originalIdPhoto != null && _originalIdPhoto != _idPhoto) {
          await PhotoStore.delete(_originalIdPhoto);
        }
      } else {
        await repo.addTenant(tenant, deposit: parseMoney(_deposit.text) ?? 0);
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

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 12),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  /// Two short fields side by side on wide screens; stacked on phones.
  /// [b] may be null, in which case [a] just takes half the width.
  Widget _pair(bool wide, Widget a, [Widget? b]) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [a, if (b != null) b],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b ?? const SizedBox.shrink()),
      ],
    );
  }

  Widget _roomPicker(ColorScheme scheme) {
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
            widget.tenant!.roomName.isEmpty ? '-' : widget.tenant!.roomName),
      );
    }
    if (!_roomsLoaded) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      );
    }
    if (_eligibleRooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          tr('No available or reserved rooms. Add a room, or check out a tenant first.'),
          style: TextStyle(color: scheme.error),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final r in _eligibleRooms)
            _RoomPickTile(
              room: r,
              selected: _roomId == r.id,
              onTap: () => _selectRoom(r),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final latest = latestDueOnOrBefore(_moveIn, todayDate());
    final showBackfill = !_editing && latest.isAfter(_moveIn);

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? tr('Edit tenant') : tr('Add tenant'))),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          // Centered and capped so the inputs don't stretch across a desktop
          // window; short fields go two per row once there is room.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 600;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---- room
                    TutorialTarget(
                      id: 'tenantForm.rooms',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Room'),
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 10),
                          _roomPicker(scheme),
                        ],
                      ),
                    ),

                    // ---- personal
                    _heading(tr('Personal details')),
                    TutorialTarget(
                      id: 'tenantForm.contact',
                      child: _pair(
                        wide,
                        appTextField(
                          controller: _name,
                          label: tr('Full name'),
                          icon: Ph.user,
                          capitalization: TextCapitalization.words,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? tr('Enter the name')
                              : null,
                        ),
                        appTextField(
                          controller: _phone,
                          label: tr('Phone / WhatsApp'),
                          icon: Ph.chatCircleText,
                          type: TextInputType.phone,
                          helper: tr('Used for WhatsApp invoices and reminders'),
                        ),
                      ),
                    ),
                    _pair(
                      wide,
                      appTextField(
                        controller: _idNumber,
                        label: tr('ID number (KTP / NIK)'),
                        icon: Ph.identificationCard,
                        type: TextInputType.number,
                      ),
                      appTextField(
                        controller: _institution,
                        label: tr('School / workplace'),
                        icon: Ph.briefcase,
                        capitalization: TextCapitalization.words,
                      ),
                    ),
                    Row(
                      children: [
                        PhotoThumb(
                          name: _idPhoto,
                          size: 72,
                          placeholderIcon: Ph.identificationCard,
                          onTap: _idPhoto == null
                              ? null
                              : () => openPhoto(context, _idPhoto!),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Ph.cameraPlus),
                                label: Text(_idPhoto == null
                                    ? tr('Add ID photo')
                                    : tr('Replace')),
                                onPressed: _pickIdPhoto,
                              ),
                              if (_idPhoto != null)
                                TextButton(
                                  onPressed: () async {
                                    if (_idPhoto != _originalIdPhoto) {
                                      await PhotoStore.delete(_idPhoto);
                                    }
                                    setState(() => _idPhoto = null);
                                  },
                                  child: Text(tr('Remove')),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _pair(
                      wide,
                      appTextField(
                        controller: _institutionAddress,
                        label: tr('School / workplace address'),
                        icon: Ph.mapPin,
                        maxLines: 2,
                      ),
                      appTextField(
                        controller: _homeAddress,
                        label: tr('Home address'),
                        icon: Ph.house,
                        maxLines: 2,
                      ),
                    ),

                    // ---- emergency
                    _heading(tr('Emergency contact')),
                    _pair(
                      wide,
                      appTextField(
                        controller: _emName,
                        label: tr('Contact name'),
                        icon: Ph.addressBook,
                        capitalization: TextCapitalization.words,
                      ),
                      appTextField(
                        controller: _emRelation,
                        label: tr('Relationship (e.g. mother, brother)'),
                        icon: Ph.usersThree,
                      ),
                    ),
                    _pair(
                      wide,
                      appTextField(
                        controller: _emPhone,
                        label: tr('Contact phone'),
                        icon: Ph.phone,
                        type: TextInputType.phone,
                      ),
                      appTextField(
                        controller: _emAddress,
                        label: tr('Contact address'),
                        icon: Ph.mapPin,
                        maxLines: 2,
                      ),
                    ),

                    // ---- lease
                    _heading(tr('Stay & rent')),
                    _pair(
                      wide,
                      DateField(
                        label: tr('Move-in date'),
                        value: _moveIn,
                        enabled: !_editing,
                        onChanged: (d) {
                          if (d != null) setState(() => _moveIn = d);
                        },
                      ),
                      DateField(
                        label: tr('End date (optional)'),
                        value: _endDate,
                        clearable: true,
                        firstDate: addDays(_moveIn, 1),
                        onChanged: (d) => setState(() => _endDate = d),
                      ),
                    ),
                    if (_editing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          tr('The move-in date can\'t be changed because invoices are already based on it.'),
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ),
                    if (showBackfill)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr('Existing tenant: bill from current period')),
                        subtitle: Text(
                          _billFromCurrent
                              ? tr('First invoice is due {date}. Old months are not created.',
                                  {'date': fmtDate(latest)})
                              : tr('Invoices will be created for every month since move-in (all unpaid).'),
                        ),
                        value: _billFromCurrent,
                        onChanged: (v) => setState(() => _billFromCurrent = v),
                      ),
                    TutorialTarget(
                      id: 'tenantForm.rent',
                      child: _pair(
                        wide,
                        moneyField(
                          controller: _rent,
                          label: tr('Rent per month'),
                          icon: Ph.money,
                          onChanged: (_) => _rentTouched = true,
                          validator: (v) {
                            final n = parseMoney(v ?? '');
                            return (n == null || n <= 0)
                                ? tr('Enter the monthly rent')
                                : null;
                          },
                          helper: _editing
                              ? tr('Changes apply to invoices created from now on')
                              : tr('Prefilled from the room price'),
                        ),
                        _editing
                            ? null
                            : moneyField(
                                controller: _deposit,
                                label: tr('Deposit received (optional)'),
                                icon: Ph.piggyBank,
                              ),
                      ),
                    ),
                    appTextField(
                      controller: _notes,
                      label: tr('Notes (optional)'),
                      icon: Ph.notePencil,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 4),
                    TutorialTarget(
                      id: 'tenantForm.save',
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_editing ? tr('Save changes') : tr('Add tenant')),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// A selectable room card for the check-in form: name, monthly price and
/// status, with a clear selected state.
class _RoomPickTile extends StatelessWidget {
  const _RoomPickTile({
    required this.room,
    required this.selected,
    required this.onTap,
  });
  final Room room;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(14);
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          width: 148,
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (selected)
                    Icon(Ph.checkCircle, size: 18, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                rp(room.price),
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              RoomStatusPill(room.status),
            ],
          ),
        ),
      ),
    );
  }
}
