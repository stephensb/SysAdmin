import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/remote_file.dart';

/// Narrow abstraction over the SFTP file operations the app needs.
///
/// The interface deliberately speaks in app-level types ([RemoteFile],
/// [Uint8List]) so that all dartssh2 coupling lives in [DartSftpFileBackend]
/// and tests can provide a pure in-memory implementation.
abstract interface class SftpFileBackend {
  /// Lists the entries of [path].
  Future<List<RemoteFile>> listDirectory(String path);

  /// Stats a single entry at [path].
  Future<RemoteFile> stat(String path);

  /// Renames / moves [oldPath] to [newPath].
  Future<void> rename(String oldPath, String newPath);

  /// Removes the file at [path].
  Future<void> remove(String path);

  /// Reads the full contents of [path].
  Future<Uint8List> readFile(String path);

  /// Writes [data] to [path], creating or truncating it.
  Future<void> writeFile(String path, Uint8List data);

  /// Closes the underlying SFTP session.
  void close();
}

/// Real [SftpFileBackend] backed by a dartssh2 [SftpClient].
class DartSftpFileBackend implements SftpFileBackend {
  final SftpClient client;

  DartSftpFileBackend(this.client);

  @override
  Future<List<RemoteFile>> listDirectory(String path) async {
    final list = await client.listdir(path);
    return list.map((file) => RemoteFile.fromStat(file, path)).toList();
  }

  @override
  Future<RemoteFile> stat(String path) async {
    final fileName = path.split('/').last;
    final parentPath = path.substring(0, path.length - fileName.length);
    final attr = await client.stat(path);

    final sftpName = SftpName(
      filename: fileName,
      longname: attr.toString(),
      attr: attr,
    );

    return RemoteFile.fromStat(sftpName, parentPath);
  }

  @override
  Future<void> rename(String oldPath, String newPath) =>
      client.rename(oldPath, newPath);

  @override
  Future<void> remove(String path) => client.remove(path);

  @override
  Future<Uint8List> readFile(String path) async {
    final file = await client.open(path, mode: SftpFileOpenMode.read);
    try {
      return await file.readBytes();
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> writeFile(String path, Uint8List data) async {
    final file = await client.open(
      path,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
    );
    try {
      await file.writeBytes(data);
    } finally {
      await file.close();
    }
  }

  @override
  void close() => client.close();
}
