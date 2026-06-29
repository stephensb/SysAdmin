import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sysadmin/data/services/sftp_service.dart';

import '../utils/in_memory_ssh.dart';

void main() {
  late InMemorySshHost host;
  late SftpService sftp;
  late Directory tempDir;

  SftpService serviceFor(InMemorySshHost h) => SftpService.withBackends(
        files: h.sftpBackend(),
        command: h.commandClient(),
      );

  setUp(() {
    host = InMemorySshHost();
    sftp = serviceFor(host);
    tempDir = Directory.systemTemp.createTempSync('sftp_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('throws when not connected', () {
    expect(SftpService().listDirectory('/'), throwsException);
  });

  group('listing & stat', () {
    test('lists directory contents', () async {
      host
        ..addDirectory('/home/user')
        ..addFile('/home/user/a.txt', content: 'aaa')
        ..addFile('/home/user/b.log', content: 'bbbb');

      final entries = await sftp.listDirectory('/home/user');
      final names = entries.map((e) => e.name).toList()..sort();

      expect(names, ['a.txt', 'b.log']);
      final aFile = entries.firstWhere((e) => e.name == 'a.txt');
      expect(aFile.size, 3);
      expect(aFile.isDirectory, isFalse);
    });

    test('stats a single file', () async {
      host.addFile('/etc/hostname', content: 'box');
      final file = await sftp.getFileInfo('/etc/hostname');
      expect(file.name, 'hostname');
      expect(file.size, 3);
    });
  });

  group('file transfer', () {
    test('uploads a local file to the remote host', () async {
      final local = File('${tempDir.path}/upload.txt')..writeAsStringSync('payload-123');

      await sftp.uploadFile(local.path, '/remote/upload.txt');

      expect(host.fileContent('/remote/upload.txt'), 'payload-123');
    });

    test('downloads a remote file to local disk', () async {
      host.addFile('/remote/download.txt', content: 'remote-bytes');
      final localPath = '${tempDir.path}/nested/download.txt';

      await sftp.downloadFile(
        remotePath: '/remote/download.txt',
        localPath: localPath,
        onProgress: (_) {},
      );

      expect(File(localPath).readAsStringSync(), 'remote-bytes');
    });

    test('round-trips upload then download', () async {
      final src = File('${tempDir.path}/src.bin')..writeAsBytesSync([1, 2, 3, 4, 5]);
      await sftp.uploadFile(src.path, '/remote/blob.bin');

      final outPath = '${tempDir.path}/out.bin';
      await sftp.downloadFile(remotePath: '/remote/blob.bin', localPath: outPath, onProgress: (_) {});

      expect(File(outPath).readAsBytesSync(), [1, 2, 3, 4, 5]);
    });

    test('copies a file, leaving the source in place', () async {
      host.addFile('/src.txt', content: 'data');
      await sftp.copyFile('/src.txt', '/dst.txt');

      expect(host.fileContent('/dst.txt'), 'data');
      expect(host.exists('/src.txt'), isTrue);
    });

    test('moves a file, removing the source', () async {
      host.addFile('/src.txt', content: 'movable');
      await sftp.moveFile('/src.txt', '/dst.txt');

      expect(host.exists('/src.txt'), isFalse);
      expect(host.fileContent('/dst.txt'), 'movable');
    });

    test('deletes a file', () async {
      host.addFile('/gone.txt', content: 'x');
      await sftp.deleteFile('/gone.txt');
      expect(host.exists('/gone.txt'), isFalse);
    });

    test('renames a file', () async {
      host.addFile('/old.txt', content: 'y');
      await sftp.renameFile('/old.txt', '/new.txt');
      expect(host.exists('/old.txt'), isFalse);
      expect(host.fileContent('/new.txt'), 'y');
    });
  });

  group('command-backed operations', () {
    test('reads users from /etc/passwd', () async {
      final users = await sftp.getUsers();
      final names = users.map((u) => u.name).toList();
      expect(names, contains('root'));
      expect(names, contains('user'));
      expect(users.firstWhere((u) => u.name == 'root').uid, '0');
    });

    test('reads groups from /etc/group', () async {
      final groups = await sftp.getGroups();
      expect(groups.map((g) => g.name), contains('sudo'));
      expect(groups.firstWhere((g) => g.name == 'sudo').gid, '27');
    });

    test('creates files and folders via shell commands', () async {
      await sftp.createFile('/tmp/new.txt');
      await sftp.createFolder('/tmp/newdir');

      expect(host.executedCommands, contains('touch /tmp/new.txt'));
      expect(host.executedCommands, contains('mkdir -p /tmp/newdir'));
    });

    test('issues chmod and chown commands', () async {
      await sftp.changePermissions('/tmp/new.txt', '644');
      await sftp.changeOwner('/tmp/new.txt', 'user', 'user', recursive: true);

      expect(host.executedCommands, contains('chmod 644 "/tmp/new.txt"'));
      expect(host.executedCommands, contains('chown -R user:user "/tmp/new.txt"'));
    });

    test('parses file details from file & stat output', () async {
      host.addFile('/home/user/notes.txt', content: 'abcd');

      final details = await sftp.getFileDetails('/home/user/notes.txt');

      expect(details.size, '4');
      expect(details.fileType, 'ASCII text');
    });
  });

  test('disconnect clears the connection', () async {
    expect(sftp.isConnected, isTrue);
    await sftp.disconnect();
    expect(sftp.isConnected, isFalse);
  });
}
