import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Photos live in <app documents>/photos. The database only stores the file
/// NAME (not the full path), so backups can be restored on another phone.
class PhotoStore {
  PhotoStore._();

  static late Directory _dir;
  static Directory get dir => _dir;

  static Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory(p.join(base.path, 'photos'));
    if (!await _dir.exists()) {
      await _dir.create(recursive: true);
    }
  }

  static File file(String name) => File(p.join(_dir.path, name));

  /// Opens camera/gallery, copies the picked image into the app folder and
  /// returns the stored file name (or null if cancelled).
  static Future<String?> pick(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, imageQuality: 75, maxWidth: 1600);
    if (picked == null) return null;
    var ext = p.extension(picked.path).toLowerCase();
    if (ext.isEmpty) ext = '.jpg';
    final name = '${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(picked.path).copy(p.join(_dir.path, name));
    return name;
  }

  static Future<void> delete(String? name) async {
    if (name == null || name.isEmpty) return;
    final f = file(name);
    if (await f.exists()) {
      await f.delete();
    }
  }
}
