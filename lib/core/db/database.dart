import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single SQLite database for the whole app.
///
/// Phase 2/3 will add tables (water usage, announcements, inspections,
/// warnings, spendings) by bumping [version] and adding an onUpgrade step.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const String fileName = 'kost.db';
  static const int version = 2;

  Future<Database>? _opening;

  Future<String> get path async => p.join(await getDatabasesPath(), fileName);

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    return openDatabase(
      await path,
      version: version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Rooms can now hold more than one tenant at once.
      await db.execute(
          "ALTER TABLE rooms ADD COLUMN capacity INTEGER NOT NULL DEFAULT 1");
    }
  }

  /// Closes the connection (used before backup/restore). It reopens lazily.
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) {
      final db = await opening;
      await db.close();
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE rooms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        price INTEGER NOT NULL,
        status TEXT NOT NULL,
        capacity INTEGER NOT NULL DEFAULT 1,
        facilities TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )''');

    await db.execute('''
      CREATE TABLE room_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        room_id INTEGER NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
        path TEXT NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE tenants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        room_id INTEGER REFERENCES rooms(id) ON DELETE SET NULL,
        room_name TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        id_number TEXT NOT NULL DEFAULT '',
        id_photo TEXT,
        institution TEXT NOT NULL DEFAULT '',
        institution_address TEXT NOT NULL DEFAULT '',
        home_address TEXT NOT NULL DEFAULT '',
        emergency_name TEXT NOT NULL DEFAULT '',
        emergency_relation TEXT NOT NULL DEFAULT '',
        emergency_phone TEXT NOT NULL DEFAULT '',
        emergency_address TEXT NOT NULL DEFAULT '',
        rent_amount INTEGER NOT NULL,
        move_in_date TEXT NOT NULL,
        billing_start TEXT NOT NULL,
        end_date TEXT,
        move_out_date TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        notes TEXT NOT NULL DEFAULT ''
      )''');

    // One row per billing period (the "invoice").
    await db.execute('''
      CREATE TABLE rent_charges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        due_date TEXT NOT NULL,
        period_end TEXT NOT NULL,
        amount INTEGER NOT NULL
      )''');
    await db.execute(
        'CREATE UNIQUE INDEX idx_charge_period ON rent_charges(tenant_id, due_date)');

    // Every payment received against an invoice (supports partial payments).
    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        charge_id INTEGER NOT NULL REFERENCES rent_charges(id) ON DELETE CASCADE,
        amount INTEGER NOT NULL,
        paid_on TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'Cash',
        proof_photo TEXT,
        note TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('CREATE INDEX idx_payments_charge ON payments(charge_id)');

    // Invoice + how much has been paid so far.
    await db.execute('''
      CREATE VIEW charge_view AS
      SELECT c.id, c.tenant_id, c.due_date, c.period_end, c.amount,
             COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.charge_id = c.id), 0) AS paid_amount,
             (SELECT MAX(p.paid_on) FROM payments p WHERE p.charge_id = c.id) AS paid_date
      FROM rent_charges c''');

    await db.execute('''
      CREATE TABLE deposits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        entry_date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }
}
