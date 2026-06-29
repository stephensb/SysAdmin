import 'dart:convert';
import 'dart:typed_data';

import 'package:sysadmin/data/models/remote_file.dart';
import 'package:sysadmin/data/services/sftp_file_backend.dart';
import 'package:sysadmin/data/services/ssh_command_client.dart';

/// A single node in the virtual filesystem.
class _Node {
  Uint8List bytes;
  String permissions; // 10-char ls-style string, e.g. '-rw-r--r--'
  final bool isDir;

  _Node({required this.bytes, required this.permissions, required this.isDir});
}

/// An in-memory fake SSH host with a virtual filesystem.
///
/// It can hand out a [SshCommandClient] (via [commandClient]) and a
/// [SftpFileBackend] (via [sftpBackend]) that share the same filesystem, so
/// command execution and file transfer can be exercised together without a
/// real server. Seed state with [addFile] / [addDirectory] and inspect what
/// ran with [executedCommands].
///
/// Example:
/// ```dart
/// final host = InMemorySshHost()..addFile('/etc/hostname', content: 'box');
/// final sftp = SftpService.withBackends(
///   files: host.sftpBackend(),
///   command: host.commandClient(),
/// );
/// ```
class InMemorySshHost {
  final Map<String, _Node> _nodes = {};

  /// Exact-match overrides: command string -> stdout. Takes priority over the
  /// built-in command handling, so tests can script arbitrary output.
  final Map<String, String> scriptedCommands = {};

  /// Per-path output for the `file "<path>"` command.
  final Map<String, String> fileCommandOutputs = {};

  /// Per-path output for the `stat "<path>"` command.
  final Map<String, String> statCommandOutputs = {};

  /// Contents returned for `cat /etc/passwd`.
  String passwdContent = 'root:x:0:0:root:/root:/bin/bash\n'
      'user:x:1000:1000:user:/home/user:/bin/bash\n';

  /// Contents returned for `cat /etc/group`.
  String groupContent = 'root:x:0:\n'
      'sudo:x:27:user\n'
      'user:x:1000:\n';

  /// Every command that was run, in order.
  final List<String> executedCommands = [];

  bool closed = false;

  // ---- Seeding helpers -----------------------------------------------------

  void addFile(String path, {String content = '', String permissions = '-rw-r--r--'}) {
    _nodes[_normalize(path)] = _Node(
      bytes: Uint8List.fromList(utf8.encode(content)),
      permissions: permissions,
      isDir: false,
    );
  }

  void addDirectory(String path, {String permissions = 'drwxr-xr-x'}) {
    _nodes[_normalize(path)] = _Node(
      bytes: Uint8List(0),
      permissions: permissions,
      isDir: true,
    );
  }

  /// Returns the stored contents of [path] as a string, or null if absent.
  String? fileContent(String path) {
    final node = _nodes[_normalize(path)];
    if (node == null || node.isDir) return null;
    return utf8.decode(node.bytes);
  }

  bool exists(String path) => _nodes.containsKey(_normalize(path));

  // ---- Backends ------------------------------------------------------------

  SshCommandClient commandClient() => _FakeCommandClient(this);

  SftpFileBackend sftpBackend() => _FakeSftpBackend(this);

  // ---- Internal ------------------------------------------------------------

  String _normalize(String path) {
    var p = path.trim();
    if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p.isEmpty ? '/' : p;
  }

  String _parentOf(String path) {
    final p = _normalize(path);
    final i = p.lastIndexOf('/');
    if (i <= 0) return '/';
    return p.substring(0, i);
  }

  String _nameOf(String path) {
    final p = _normalize(path);
    return p.substring(p.lastIndexOf('/') + 1);
  }

  RemoteFile _toRemoteFile(String path, _Node node) => RemoteFile(
        name: _nameOf(path),
        path: _normalize(path),
        type: node.isDir ? FileType.directory : FileType.file,
        permissions: node.permissions,
        size: node.bytes.length,
      );

  String _unquote(String value) {
    var v = value.trim();
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }

  /// Interprets a command against the virtual filesystem and returns stdout.
  String runCommand(String command) {
    executedCommands.add(command);
    final cmd = command.trim();

    if (scriptedCommands.containsKey(cmd)) return scriptedCommands[cmd]!;

    if (cmd == 'cat /etc/passwd') return passwdContent;
    if (cmd == 'cat /etc/group') return groupContent;

    if (cmd.startsWith('echo ')) {
      return '${_unquote(cmd.substring('echo '.length))}\n';
    }
    if (cmd.startsWith('touch ')) {
      addFile(_unquote(cmd.substring('touch '.length)));
      return '';
    }
    if (cmd.startsWith('mkdir -p ')) {
      addDirectory(_unquote(cmd.substring('mkdir -p '.length)));
      return '';
    }
    if (cmd.startsWith('mkdir ')) {
      addDirectory(_unquote(cmd.substring('mkdir '.length)));
      return '';
    }
    if (cmd.startsWith('chmod ') || cmd.startsWith('chown ')) {
      return ''; // success => empty output
    }
    if (cmd.startsWith('file ')) {
      final path = _unquote(cmd.substring('file '.length));
      return fileCommandOutputs[path] ?? '$path: ASCII text\n';
    }
    if (cmd.startsWith('stat ')) {
      final path = _unquote(cmd.substring('stat '.length));
      return statCommandOutputs[path] ?? _defaultStat(path);
    }

    return ''; // unknown command => treated as success with no output
  }

  String _defaultStat(String path) {
    final node = _nodes[_normalize(path)];
    final size = node?.bytes.length ?? 0;
    return '  File: ${_nameOf(path)}\n'
        '  Size: $size            Blocks: 8          IO Block: 4096   regular file\n'
        'Device: 801h/2049d      Inode: 12345       Links: 1\n'
        'Access: (0644/-rw-r--r--)  Uid: ( 1000/    user)   Gid: ( 1000/    user)\n'
        'Access: 2024-01-01 12:00:00.000000000 +0000\n'
        'Modify: 2024-01-01 12:00:00.000000000 +0000\n'
        'Change: 2024-01-01 12:00:00.000000000 +0000\n'
        ' Birth: 2024-01-01 12:00:00.000000000 +0000\n';
  }

  // ---- SFTP primitives (used by _FakeSftpBackend) --------------------------

  List<RemoteFile> _listDir(String path) {
    final parent = _normalize(path);
    final result = <RemoteFile>[];
    _nodes.forEach((key, node) {
      if (_parentOf(key) == parent && key != parent) {
        result.add(_toRemoteFile(key, node));
      }
    });
    return result;
  }

  RemoteFile _stat(String path) {
    final node = _nodes[_normalize(path)];
    if (node == null) {
      throw Exception('No such file or directory: $path');
    }
    return _toRemoteFile(path, node);
  }

  Uint8List _read(String path) {
    final node = _nodes[_normalize(path)];
    if (node == null || node.isDir) {
      throw Exception('No such file: $path');
    }
    return node.bytes;
  }

  void _write(String path, Uint8List data) {
    _nodes[_normalize(path)] = _Node(
      bytes: Uint8List.fromList(data),
      permissions: '-rw-r--r--',
      isDir: false,
    );
  }

  void _remove(String path) {
    if (_nodes.remove(_normalize(path)) == null) {
      throw Exception('No such file: $path');
    }
  }

  void _rename(String oldPath, String newPath) {
    final node = _nodes.remove(_normalize(oldPath));
    if (node == null) {
      throw Exception('No such file: $oldPath');
    }
    _nodes[_normalize(newPath)] = node;
  }
}

class _FakeCommandClient implements SshCommandClient {
  final InMemorySshHost host;

  _FakeCommandClient(this.host);

  @override
  Future<Uint8List> run(String command) async {
    if (host.closed) throw Exception('Connection closed');
    return Uint8List.fromList(utf8.encode(host.runCommand(command)));
  }

  @override
  bool get isClosed => host.closed;

  @override
  void close() => host.closed = true;
}

class _FakeSftpBackend implements SftpFileBackend {
  final InMemorySshHost host;

  _FakeSftpBackend(this.host);

  @override
  Future<List<RemoteFile>> listDirectory(String path) async => host._listDir(path);

  @override
  Future<RemoteFile> stat(String path) async => host._stat(path);

  @override
  Future<void> rename(String oldPath, String newPath) async => host._rename(oldPath, newPath);

  @override
  Future<void> remove(String path) async => host._remove(path);

  @override
  Future<Uint8List> readFile(String path) async => host._read(path);

  @override
  Future<void> writeFile(String path, Uint8List data) async => host._write(path, data);

  @override
  void close() => host.closed = true;
}
