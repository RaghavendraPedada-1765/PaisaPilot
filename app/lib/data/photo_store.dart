import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Transaction photos, kept in the app's private storage (other apps cannot
/// read it, and Android backup is off for this app). The database stores only
/// the file name.
class PhotoStore {
  PhotoStore([Future<Directory> Function()? base]) : _base = base ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _base;

  Future<Directory> _dir() async {
    final dir = Directory('${(await _base()).path}${Platform.pathSeparator}photos');
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> file(String name) async => File('${(await _dir()).path}${Platform.pathSeparator}$name');

  /// Copies a picked or captured image in; returns its file name.
  Future<String> save(String sourcePath) async {
    final dot = sourcePath.lastIndexOf('.');
    final ext = dot > sourcePath.lastIndexOf(Platform.pathSeparator) ? sourcePath.substring(dot) : '.jpg';
    final name = '${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(sourcePath).copy((await file(name)).path);
    return name;
  }

  Future<void> remove(String name) async {
    final f = await file(name);
    if (await f.exists()) await f.delete();
  }
}

final photoStore = PhotoStore();
