import 'package:sqflite/sqflite.dart';

import '../core/db/database.dart';
import '../core/utils/date_helpers.dart';
import '../core/utils/format.dart';
import '../core/utils/photo_store.dart';
import 'models.dart';
import '../core/i18n/app_language.dart';

/// An error with a message that is safe to show to the owner.
class KostException implements Exception {
  KostException(this.message);
  final String message;

  @override
  String toString() => message;
}

class KostRepository {
  KostRepository(this._appDb);

  final AppDatabase _appDb;
  Future<Database> get _db => _appDb.database;

  // ---------------------------------------------------------------- rooms

  Future<List<Room>> getRooms() async {
    final db = await _db;
    final rows = await db.query('rooms');
    final rooms = rows.map(Room.fromMap).toList();
    rooms.sort((a, b) => naturalCompare(a.name, b.name));
    return rooms;
  }

  Future<Room?> getRoom(int id) async {
    final db = await _db;
    final rows =
        await db.query('rooms', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Room.fromMap(rows.first);
  }

  Future<List<RoomOverview>> getRoomOverviews() async {
    await ensureCharges();
    final db = await _db;
    final rooms = await getRooms();

    final tenantRows = await db.query('tenants', where: 'is_active = 1');
    final byRoom = <int, List<Tenant>>{};
    for (final t in tenantRows.map(Tenant.fromMap)) {
      if (t.roomId != null) {
        byRoom.putIfAbsent(t.roomId!, () => []).add(t);
      }
    }

    final coverRows = await db.rawQuery(
        'SELECT room_id, path FROM room_photos WHERE id IN (SELECT MIN(id) FROM room_photos GROUP BY room_id)');
    final covers = <int, String>{
      for (final r in coverRows) r['room_id'] as int: r['path'] as String,
    };

    final nextDues = await _nextDueMap();

    return rooms.map((room) {
      final tenants = byRoom[room.id] ?? const <Tenant>[];
      DateTime? earliest;
      for (final t in tenants) {
        final due = nextDues[t.id];
        if (due != null && (earliest == null || due.isBefore(earliest))) {
          earliest = due;
        }
      }
      return RoomOverview(
        room: room,
        tenants: tenants,
        coverPhoto: covers[room.id],
        nextDue: earliest,
      );
    }).toList();
  }

  Future<int> insertRoom(Room room) async {
    final db = await _db;
    try {
      return await db.insert('rooms', room.toMap());
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw KostException(
            tr('A room named "{name}" already exists.', {'name': room.name}));
      }
      rethrow;
    }
  }

  Future<void> updateRoom(Room room) async {
    final db = await _db;
    try {
      await db.transaction((txn) async {
        await txn.update('rooms', room.toMap(),
            where: 'id = ?', whereArgs: [room.id]);
        // keep the room-name snapshot on tenants in sync
        await txn.update('tenants', {'room_name': room.name},
            where: 'room_id = ?', whereArgs: [room.id]);
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw KostException(
            tr('A room named "{name}" already exists.', {'name': room.name}));
      }
      rethrow;
    }
  }

  Future<void> deleteRoom(int id) async {
    final db = await _db;
    final active = await db.query('tenants',
        where: 'room_id = ? AND is_active = 1', whereArgs: [id], limit: 1);
    if (active.isNotEmpty) {
      throw KostException(
          tr('This room has a tenant. Check the tenant out before deleting the room.'));
    }
    final photos = await getRoomPhotos(id);
    await db.delete('rooms', where: 'id = ?', whereArgs: [id]);
    for (final p in photos) {
      await PhotoStore.delete(p.path);
    }
  }

  Future<List<RoomPhoto>> getRoomPhotos(int roomId) async {
    final db = await _db;
    final rows = await db.query('room_photos',
        where: 'room_id = ?', whereArgs: [roomId], orderBy: 'id');
    return rows.map(RoomPhoto.fromMap).toList();
  }

  Future<void> addRoomPhoto(int roomId, String path) async {
    final db = await _db;
    await db.insert('room_photos', {'room_id': roomId, 'path': path});
  }

  Future<void> deleteRoomPhoto(RoomPhoto photo) async {
    final db = await _db;
    await db.delete('room_photos', where: 'id = ?', whereArgs: [photo.id]);
    await PhotoStore.delete(photo.path);
  }

  // -------------------------------------------------------------- tenants

  Future<Tenant?> getTenant(int id) async {
    final db = await _db;
    final rows =
        await db.query('tenants', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Tenant.fromMap(rows.first);
  }

  Future<List<TenantOverview>> getTenantOverviews() async {
    await ensureCharges();
    final db = await _db;
    final rows = await db.query('tenants');
    final tenants = rows.map(Tenant.fromMap).toList();
    tenants.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final nextDues = await _nextDueMap();
    final sums = await db.rawQuery(
        'SELECT tenant_id, SUM(amount - paid_amount) AS s, '
        'SUM(CASE WHEN due_date < ? THEN 1 ELSE 0 END) AS o '
        'FROM charge_view WHERE paid_amount < amount GROUP BY tenant_id',
        [toDb(todayDate())]);
    final outstanding = <int, int>{};
    final overdue = <int, int>{};
    for (final r in sums) {
      final id = r['tenant_id'] as int;
      outstanding[id] = (r['s'] as int?) ?? 0;
      overdue[id] = (r['o'] as int?) ?? 0;
    }

    return tenants.map((t) {
      return TenantOverview(
        tenant: t,
        nextDue: t.isActive ? nextDues[t.id] : null,
        outstanding: outstanding[t.id] ?? 0,
        overdueCount: overdue[t.id] ?? 0,
      );
    }).toList();
  }

  Future<int> addTenant(Tenant t, {required int deposit}) async {
    if (t.roomId == null) throw KostException(tr('Select a room first.'));
    final db = await _db;
    final id = await db.transaction<int>((txn) async {
      final roomRows = await txn
          .query('rooms', where: 'id = ?', whereArgs: [t.roomId], limit: 1);
      if (roomRows.isEmpty) throw KostException(tr('Room not found.'));
      final room = Room.fromMap(roomRows.first);
      if (room.status == RoomStatus.maintenance) {
        throw KostException(
            tr('This room is under maintenance. Change its status first.'));
      }
      final activeCountRows = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM tenants WHERE room_id = ? AND is_active = 1',
          [t.roomId]);
      final activeCount = (activeCountRows.first['c'] as int?) ?? 0;
      if (activeCount >= room.capacity) {
        throw KostException(room.capacity <= 1
            ? tr('This room already has a tenant.')
            : tr('This room is already full ({n} tenants max).',
                {'n': room.capacity}));
      }

      final map = t.toMap();
      map['room_name'] = room.name;
      final tenantId = await txn.insert('tenants', map);

      final newCount = activeCount + 1;
      await txn.update(
          'rooms',
          {
            'status': newCount >= room.capacity
                ? RoomStatus.occupied.name
                : RoomStatus.available.name
          },
          where: 'id = ?',
          whereArgs: [t.roomId]);

      if (deposit > 0) {
        await txn.insert('deposits', {
          'tenant_id': tenantId,
          'type': DepositType.received.name,
          'amount': deposit,
          'entry_date': toDb(t.moveInDate),
          'note': 'Deposit at move-in',
        });
      }
      return tenantId;
    });
    await ensureCharges();
    return id;
  }

  Future<void> updateTenant(Tenant t) async {
    final db = await _db;
    await db.update('tenants', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
  }

  /// Ends the stay: settles the deposit, frees the room, removes future
  /// unpaid invoices. Overdue invoices stay on the ledger.
  Future<void> checkoutTenant({
    required int tenantId,
    required DateTime moveOut,
    required int deduction,
    String deductionNote = '',
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('tenants',
          where: 'id = ?', whereArgs: [tenantId], limit: 1);
      if (rows.isEmpty) throw KostException(tr('Tenant not found.'));
      final tenant = Tenant.fromMap(rows.first);
      if (!tenant.isActive) throw KostException(tr('Tenant already checked out.'));

      final held = await _depositHeld(txn, tenantId);
      if (deduction > held) {
        throw KostException(
            tr('Deduction is more than the deposit held ({amount}).',
                {'amount': rp(held)}));
      }
      final date = toDb(moveOut);

      if (deduction > 0) {
        await txn.insert('deposits', {
          'tenant_id': tenantId,
          'type': DepositType.deduction.name,
          'amount': deduction,
          'entry_date': date,
          'note': deductionNote.isEmpty ? 'Deduction at check-out' : deductionNote,
        });
      }
      final refund = held - deduction;
      if (refund > 0) {
        await txn.insert('deposits', {
          'tenant_id': tenantId,
          'type': DepositType.refund.name,
          'amount': refund,
          'entry_date': date,
          'note': 'Refund at check-out',
        });
      }

      await txn.update('tenants', {'is_active': 0, 'move_out_date': date},
          where: 'id = ?', whereArgs: [tenantId]);

      await txn.rawDelete(
          'DELETE FROM rent_charges WHERE tenant_id = ? AND due_date > ? '
          'AND id NOT IN (SELECT charge_id FROM payments)',
          [tenantId, date]);

      if (tenant.roomId != null) {
        final roomRows = await txn.query('rooms',
            where: 'id = ?', whereArgs: [tenant.roomId], limit: 1);
        if (roomRows.isNotEmpty) {
          final room = Room.fromMap(roomRows.first);
          if (room.status != RoomStatus.maintenance) {
            final remainingRows = await txn.rawQuery(
                'SELECT COUNT(*) AS c FROM tenants WHERE room_id = ? AND is_active = 1',
                [tenant.roomId]);
            final remaining = (remainingRows.first['c'] as int?) ?? 0;
            await txn.update(
                'rooms',
                {
                  'status': remaining >= room.capacity && room.capacity > 0
                      ? RoomStatus.occupied.name
                      : RoomStatus.available.name
                },
                where: 'id = ?',
                whereArgs: [tenant.roomId]);
          }
        }
      }
    });
  }

  /// Permanently deletes a FORMER tenant together with invoices, payments and
  /// deposit entries.
  Future<void> deleteTenant(int id) async {
    final db = await _db;
    final tenant = await getTenant(id);
    if (tenant == null) return;
    if (tenant.isActive) {
      throw KostException(tr('Check the tenant out first.'));
    }
    final proofRows = await db.rawQuery(
        'SELECT p.proof_photo AS f FROM payments p '
        'JOIN rent_charges c ON c.id = p.charge_id '
        'WHERE c.tenant_id = ? AND p.proof_photo IS NOT NULL',
        [id]);
    await db.delete('tenants', where: 'id = ?', whereArgs: [id]);
    await PhotoStore.delete(tenant.idPhoto);
    for (final r in proofRows) {
      await PhotoStore.delete(r['f'] as String?);
    }
  }

  // -------------------------------------------------------------- deposits

  Future<int> _depositHeld(DatabaseExecutor ex, int tenantId) async {
    final rows = await ex.rawQuery(
        "SELECT COALESCE(SUM(CASE type WHEN 'received' THEN amount ELSE -amount END), 0) AS s "
        'FROM deposits WHERE tenant_id = ?',
        [tenantId]);
    return (rows.first['s'] as int?) ?? 0;
  }

  Future<int> depositHeld(int tenantId) async => _depositHeld(await _db, tenantId);

  Future<List<DepositEntry>> getDeposits(int tenantId) async {
    final db = await _db;
    final rows = await db.query('deposits',
        where: 'tenant_id = ?',
        whereArgs: [tenantId],
        orderBy: 'entry_date DESC, id DESC');
    return rows.map(DepositEntry.fromMap).toList();
  }

  Future<void> addDeposit({
    required int tenantId,
    required DepositType type,
    required int amount,
    required DateTime date,
    String note = '',
  }) async {
    if (amount <= 0) throw KostException(tr('Enter an amount.'));
    final db = await _db;
    if (type != DepositType.received) {
      final held = await _depositHeld(db, tenantId);
      if (amount > held) {
        throw KostException(tr('That is more than the deposit held ({amount}).',
            {'amount': rp(held)}));
      }
    }
    await db.insert('deposits', {
      'tenant_id': tenantId,
      'type': type.name,
      'amount': amount,
      'entry_date': toDb(date),
      'note': note,
    });
  }

  Future<void> deleteDeposit(int id) async {
    final db = await _db;
    await db.delete('deposits', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------- rent ledger

  Future<void>? _ensureRun;

  /// Creates any missing invoices for active tenants (up to 7 days ahead).
  /// Safe to call often; concurrent calls share one run and the unique index
  /// prevents duplicates.
  Future<void> ensureCharges() {
    return _ensureRun ??= _generateCharges().whenComplete(() => _ensureRun = null);
  }

  Future<void> _generateCharges() async {
    final db = await _db;
    final horizon = addDays(todayDate(), 7);
    final tenants = (await db.query('tenants', where: 'is_active = 1'))
        .map(Tenant.fromMap)
        .toList();

    final batch = db.batch();
    var pending = false;

    for (final t in tenants) {
      final existingRows = await db.query('rent_charges',
          columns: ['due_date'], where: 'tenant_id = ?', whereArgs: [t.id]);
      final existing = existingRows.map((r) => r['due_date'] as String).toSet();

      for (var n = 0;; n++) {
        final due = addMonthsAnchored(t.moveInDate, n);
        if (due.isAfter(horizon)) break;
        if (t.endDate != null && !due.isBefore(t.endDate!)) break;
        if (due.isBefore(t.billingStart)) continue;
        if (existing.contains(toDb(due))) continue;

        var periodEnd = addDays(addMonthsAnchored(t.moveInDate, n + 1), -1);
        if (t.endDate != null && periodEnd.isAfter(t.endDate!)) {
          periodEnd = t.endDate!;
        }
        batch.insert(
          'rent_charges',
          {
            'tenant_id': t.id,
            'due_date': toDb(due),
            'period_end': toDb(periodEnd),
            'amount': t.rentAmount,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        pending = true;
      }
    }
    if (pending) {
      await batch.commit(noResult: true);
    }
  }

  static const String _chargeSelect = '''
    SELECT c.*, t.name AS tenant_name, t.room_name AS room_name, t.phone AS tenant_phone
    FROM charge_view c JOIN tenants t ON t.id = c.tenant_id''';

  Future<List<ChargeView>> getCharges({int? tenantId}) async {
    await ensureCharges();
    final db = await _db;
    final rows = await db.rawQuery(
      '$_chargeSelect ${tenantId == null ? '' : 'WHERE c.tenant_id = ?'} '
      'ORDER BY c.due_date DESC, c.id DESC',
      tenantId == null ? null : [tenantId],
    );
    return rows.map(ChargeView.fromMap).toList();
  }

  Future<ChargeView?> getCharge(int id) async {
    final db = await _db;
    final rows = await db.rawQuery('$_chargeSelect WHERE c.id = ?', [id]);
    return rows.isEmpty ? null : ChargeView.fromMap(rows.first);
  }

  /// Earliest unpaid invoice per active tenant; if everything is paid, the
  /// next scheduled due date.
  Future<Map<int, DateTime>> _nextDueMap() async {
    final db = await _db;
    final result = <int, DateTime>{};

    final unpaid = await db.rawQuery(
        'SELECT tenant_id, MIN(due_date) AS d FROM charge_view '
        'WHERE paid_amount < amount '
        'AND tenant_id IN (SELECT id FROM tenants WHERE is_active = 1) '
        'GROUP BY tenant_id');
    for (final r in unpaid) {
      result[r['tenant_id'] as int] = fromDb(r['d'] as String);
    }

    final latestRows = await db.rawQuery(
        'SELECT tenant_id, MAX(due_date) AS d FROM rent_charges GROUP BY tenant_id');
    final latest = <int, DateTime>{
      for (final r in latestRows) r['tenant_id'] as int: fromDb(r['d'] as String),
    };

    final tenants = (await db.query('tenants', where: 'is_active = 1'))
        .map(Tenant.fromMap);
    for (final t in tenants) {
      if (result.containsKey(t.id)) continue;
      final last = latest[t.id];
      if (last == null) continue;
      final idx = monthsBetween(t.moveInDate, last);
      final next = addMonthsAnchored(t.moveInDate, idx + 1);
      if (t.endDate != null && !next.isBefore(t.endDate!)) continue;
      result[t.id!] = next;
    }
    return result;
  }

  Future<void> updateChargeAmount(int chargeId, int amount) async {
    final charge = await getCharge(chargeId);
    if (charge == null) throw KostException(tr('Invoice not found.'));
    if (amount < charge.charge.paidAmount) {
      throw KostException(
          tr('Amount cannot be lower than what was already paid ({amount}).',
              {'amount': rp(charge.charge.paidAmount)}));
    }
    final db = await _db;
    await db.update('rent_charges', {'amount': amount},
        where: 'id = ?', whereArgs: [chargeId]);
  }

  // -------------------------------------------------------------- payments

  Future<List<Payment>> getPayments(int chargeId) async {
    final db = await _db;
    final rows = await db.query('payments',
        where: 'charge_id = ?',
        whereArgs: [chargeId],
        orderBy: 'paid_on DESC, id DESC');
    return rows.map(Payment.fromMap).toList();
  }

  Future<void> addPayment({
    required int chargeId,
    required int amount,
    required DateTime date,
    required String method,
    String? proofPhoto,
    String note = '',
  }) async {
    if (amount <= 0) throw KostException(tr('Enter an amount.'));
    final view = await getCharge(chargeId);
    if (view == null) throw KostException(tr('Invoice not found.'));
    if (amount > view.charge.remaining) {
      throw KostException(
          tr('Amount is more than the remaining balance ({amount}).',
              {'amount': rp(view.charge.remaining)}));
    }
    final db = await _db;
    await db.insert('payments', {
      'charge_id': chargeId,
      'amount': amount,
      'paid_on': toDb(date),
      'method': method,
      'proof_photo': proofPhoto,
      'note': note,
    });
  }

  Future<void> deletePayment(Payment payment) async {
    final db = await _db;
    await db.delete('payments', where: 'id = ?', whereArgs: [payment.id]);
    await PhotoStore.delete(payment.proofPhoto);
  }

  /// Total received in [from, toExclusive).
  Future<int> collectedBetween(DateTime from, DateTime toExclusive) async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
        'WHERE paid_on >= ? AND paid_on < ?',
        [toDb(from), toDb(toExclusive)]);
    return (rows.first['s'] as int?) ?? 0;
  }

  // -------------------------------------------------------------- settings

  Future<String?> _getSetting(String key) async {
    final db = await _db;
    final rows = await db
        .query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _setSetting(String key, String value) async {
    final db = await _db;
    await db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<KostProfile> getProfile() async {
    return KostProfile(
      name: await _getSetting('kost_name') ?? '',
      paymentInfo: await _getSetting('payment_info') ?? '',
    );
  }

  Future<void> saveProfile(KostProfile profile) async {
    await _setSetting('kost_name', profile.name);
    await _setSetting('payment_info', profile.paymentInfo);
  }

  /// 'system', 'light' or 'dark'. Stored as plain text so this data layer
  /// doesn't need to depend on Flutter's ThemeMode type.
  /// When the owner last created a backup (null = never).
  Future<DateTime?> getLastBackup() async =>
      fromDbN(await _getSetting('last_backup'));

  Future<void> markBackupDone() => _setSetting('last_backup', toDb(todayDate()));

  Future<String> getThemeModeSetting() async {
    return await _getSetting('theme_mode') ?? 'system';
  }

  Future<void> setThemeModeSetting(String value) async {
    await _setSetting('theme_mode', value);
  }

  /// 'id' or 'en'. Indonesian is the default until the owner changes it.
  Future<String> getLanguageSetting() async {
    return await _getSetting('language') ?? AppLanguage.id.code;
  }

  Future<void> setLanguageSetting(String code) async {
    await _setSetting('language', code);
  }

  /// Whether the first-run walkthrough has been finished or skipped.
  Future<bool> getTutorialDone() async {
    return (await _getSetting('tutorial_done')) == '1';
  }

  Future<void> setTutorialDone(bool done) async {
    await _setSetting('tutorial_done', done ? '1' : '0');
  }

  // ---------------------------------------------------------------- export

  Future<String> exportChargesCsv() async {
    final charges = await getCharges();
    final rows = <List<Object?>>[
      [
        tr('Tenant'),
        tr('Room'),
        tr('Period start (due date)'),
        tr('Period end'),
        tr('Amount'),
        tr('Paid'),
        tr('Remaining'),
        tr('Last payment date'),
        tr('Status'),
      ],
      for (final v in charges)
        [
          v.tenantName,
          v.roomName,
          toDb(v.charge.dueDate),
          toDb(v.charge.periodEnd),
          v.charge.amount,
          v.charge.paidAmount,
          v.charge.remaining,
          v.charge.paidDate == null ? '' : toDb(v.charge.paidDate!),
          v.charge.statusOn(todayDate()).label,
        ],
    ];
    return rows.map((r) => r.map(_csvCell).join(',')).join('\n');
  }

  String _csvCell(Object? v) {
    final s = '${v ?? ''}';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
