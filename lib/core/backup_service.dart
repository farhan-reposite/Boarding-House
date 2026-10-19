import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import 'db/database.dart';
import 'utils/date_helpers.dart';
import 'utils/photo_store.dart';
import 'i18n/app_language.dart';

/// A backup is a single .zip containing the SQLite file and every photo.
class BackupService {
  BackupService._();

  static Future<File> createBackup() async {
    // Close the DB so the file on disk is complete; it reopens on next use.
    await AppDatabase.instance.close();

    final archive = Archive();
    final dbFile = File(await AppDatabase.instance.path);
    if (await dbFile.exists()) {
      final bytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile(AppDatabase.fileName, bytes.length, bytes));
    }
    if (await PhotoStore.dir.exists()) {
      await for (final entity in PhotoStore.dir.list()) {
        if (entity is File) {
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(
              'photos/${p.basename(entity.path)}', bytes.length, bytes));
        }
      }
    }

    final data = ZipEncoder().encode(archive)!;
    final tmp = await getTemporaryDirectory();
    final out = File(p.join(tmp.path, 'kost_backup_${toDb(todayDate())}.zip'));
    await out.writeAsBytes(data, flush: true);
    return out;
  }

  static Future<void> shareBackup() async {
    final file = await createBackup();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        subject: 'Kost backup ${toDb(todayDate())}',
        text: tr('Kost app backup. Keep this file somewhere safe (Google Drive, email to yourself).'),
      ),
    );
    await KostRepository(AppDatabase.instance).markBackupDone();
  }

  /// Replaces ALL current data with the contents of [zipFile].
  static Future<void> restoreBackup(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? dbEntry;
    for (final f in archive.files) {
      if (f.isFile && f.name == AppDatabase.fileName) dbEntry = f;
    }
    if (dbEntry == null) {
      throw KostException(tr('This file is not a Kost backup (no database inside).'));
    }
    final dbBytes = dbEntry.content as List<int>;
    if (dbBytes.length < 16 ||
        String.fromCharCodes(dbBytes.take(15)) != 'SQLite format 3') {
      throw KostException(tr('The database inside this backup is not valid.'));
    }

    await AppDatabase.instance.close();
    final dbPath = await AppDatabase.instance.path;

    for (final suffix in ['-wal', '-shm', '-journal']) {
      final leftover = File('$dbPath$suffix');
      if (await leftover.exists()) await leftover.delete();
    }
    await File(dbPath).writeAsBytes(dbBytes, flush: true);

    final photoDir = PhotoStore.dir;
    if (await photoDir.exists()) {
      await photoDir.delete(recursive: true);
    }
    await photoDir.create(recursive: true);
    for (final f in archive.files) {
      if (f.isFile && f.name.startsWith('photos/')) {
        final data = f.content as List<int>;
        await File(p.join(photoDir.path, p.basename(f.name)))
            .writeAsBytes(data, flush: true);
      }
    }
  }

  static Future<void> shareCsv(KostRepository repo) async {
    final csv = await repo.exportChargesCsv();
    final tmp = await getTemporaryDirectory();
    final file = File(p.join(tmp.path, 'kost_payments_${toDb(todayDate())}.csv'));
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Kost payments export',
      ),
    );
  }
}
