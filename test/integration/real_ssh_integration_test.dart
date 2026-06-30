import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sysadmin/data/models/ssh_connection.dart';
import 'package:sysadmin/data/services/sftp_service.dart';

/// Opt-in integration test that talks to a REAL SSH server.
///
/// It is skipped unless the connection details are supplied via environment
/// variables, so it never runs in CI by default:
///
/// ```sh
/// SSH_IT_HOST=192.168.1.10 SSH_IT_USER=me SSH_IT_PASS=secret \
///   flutter test test/integration/real_ssh_integration_test.dart
/// ```
///
/// A quick way to get a throwaway server locally:
/// ```sh
/// docker run -d --name sysadmin-sshd -p 2222:22 \
///   -e USER_NAME=me -e USER_PASSWORD=secret -e PASSWORD_ACCESS=true \
///   lscr.io/linuxserver/openssh-server
/// ```
/// then run with `SSH_IT_HOST=127.0.0.1 SSH_IT_PORT=2222 SSH_IT_USER=me SSH_IT_PASS=secret`.
///
/// Supported environment variables:
///  - `SSH_IT_HOST` (required), `SSH_IT_USER` (required), `SSH_IT_PASS` (required)
///  - `SSH_IT_PORT` (default 22)
///  - `SSH_IT_ROOT=true` to also run the chown test (needs root privileges)
void main() {
  final env = Platform.environment;
  final host = env['SSH_IT_HOST'];
  final user = env['SSH_IT_USER'];
  final password = env['SSH_IT_PASS'];
  final port = int.tryParse(env['SSH_IT_PORT'] ?? '22') ?? 22;
  final isRoot = env['SSH_IT_ROOT'] == 'true';

  final skipReason = (host == null || user == null || password == null)
      ? 'set SSH_IT_HOST, SSH_IT_USER and SSH_IT_PASS to run this integration test'
      : null;

  group('real SSH connection', () {
    late SftpService sftp;
    late Directory tempDir;
    late String remoteDir;

    String remote(String name) => '$remoteDir/$name';

    // Writes a local temp file and returns its path.
    String localFile(String name, {String? text, List<int>? bytes}) {
      final file = File('${tempDir.path}/$name');
      if (bytes != null) {
        file.writeAsBytesSync(bytes);
      } else {
        file.writeAsStringSync(text ?? '');
      }
      return file.path;
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('real_ssh_');
      remoteDir = '/tmp/sysadmin_it_${DateTime.now().microsecondsSinceEpoch}';

      sftp = SftpService();
      await sftp.connect(SSHConnection(
        name: 'integration',
        host: host!,
        port: port,
        username: user!,
        password: password,
      ));

      // Isolated remote workspace for this test run.
      await sftp.createFolder(remoteDir);
    });

    tearDown(() async {
      // Best-effort cleanup; ignore failures so a half-finished test still tears down.
      try {
        final entries = await sftp.listDirectory(remoteDir);
        for (final entry in entries) {
          if (!entry.isDirectory) {
            try {
              await sftp.deleteFile(entry.path);
            } catch (_) {/* ignore */}
          }
        }
      } catch (_) {/* ignore */}

      await sftp.disconnect();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    group('commands', () {
      test('reads users from /etc/passwd', () async {
        final users = await sftp.getUsers();
        expect(users, isNotEmpty);
        expect(users.map((u) => u.name), contains('root'));
      });

      test('reads groups from /etc/group', () async {
        final groups = await sftp.getGroups();
        expect(groups, isNotEmpty);
        expect(groups.map((g) => g.name), contains('root'));
      });
    });

    group('file transfer', () {
      test('round-trips a text file', () async {
        final src = localFile('payload.txt', text: 'hello-from-test');
        await sftp.uploadFile(src, remote('payload.txt'));

        final outPath = '${tempDir.path}/roundtrip.txt';
        await sftp.downloadFile(remotePath: remote('payload.txt'), localPath: outPath, onProgress: (_) {});

        expect(File(outPath).readAsStringSync(), 'hello-from-test');
      });

      test('round-trips binary content byte-for-byte', () async {
        final bytes = Uint8List.fromList(List<int>.generate(256, (i) => i));
        final src = localFile('blob.bin', bytes: bytes);
        await sftp.uploadFile(src, remote('blob.bin'));

        final outPath = '${tempDir.path}/blob_out.bin';
        await sftp.downloadFile(remotePath: remote('blob.bin'), localPath: outPath, onProgress: (_) {});

        expect(File(outPath).readAsBytesSync(), bytes);
      });

      test('downloading a missing file throws', () async {
        expect(
          sftp.downloadFile(
            remotePath: remote('does_not_exist.txt'),
            localPath: '${tempDir.path}/missing.txt',
            onProgress: (_) {},
          ),
          throwsException,
        );
      });
    });

    group('filesystem operations', () {
      test('lists an uploaded file in the directory', () async {
        await sftp.uploadFile(localFile('listed.txt', text: 'x'), remote('listed.txt'));

        final entries = await sftp.listDirectory(remoteDir);
        expect(entries.map((e) => e.name), contains('listed.txt'));
      });

      test('stats a file and reports its size', () async {
        await sftp.uploadFile(localFile('sized.txt', text: 'abcde'), remote('sized.txt'));

        final info = await sftp.getFileInfo(remote('sized.txt'));
        expect(info.name, 'sized.txt');
        expect(info.size, 5);
      });

      test('creates and lists a subfolder', () async {
        await sftp.createFolder(remote('subdir'));

        final entries = await sftp.listDirectory(remoteDir);
        final dir = entries.firstWhere((e) => e.name == 'subdir');
        expect(dir.isDirectory, isTrue);
      });

      test('creates then deletes a file', () async {
        await sftp.createFile(remote('temp.txt'));
        expect((await sftp.listDirectory(remoteDir)).map((e) => e.name), contains('temp.txt'));

        await sftp.deleteFile(remote('temp.txt'));
        expect((await sftp.listDirectory(remoteDir)).map((e) => e.name), isNot(contains('temp.txt')));
      });

      test('renames a file', () async {
        await sftp.uploadFile(localFile('before.txt', text: 'r'), remote('before.txt'));

        await sftp.renameFile(remote('before.txt'), remote('after.txt'));

        final names = (await sftp.listDirectory(remoteDir)).map((e) => e.name);
        expect(names, contains('after.txt'));
        expect(names, isNot(contains('before.txt')));
      });

      test('copies a file, leaving the source in place', () async {
        await sftp.uploadFile(localFile('orig.txt', text: 'copy-me'), remote('orig.txt'));

        await sftp.copyFile(remote('orig.txt'), remote('copy.txt'));

        final names = (await sftp.listDirectory(remoteDir)).map((e) => e.name).toSet();
        expect(names, containsAll(['orig.txt', 'copy.txt']));

        final out = '${tempDir.path}/copy_check.txt';
        await sftp.downloadFile(remotePath: remote('copy.txt'), localPath: out, onProgress: (_) {});
        expect(File(out).readAsStringSync(), 'copy-me');
      });

      test('moves a file, removing the source', () async {
        await sftp.uploadFile(localFile('movable.txt', text: 'move-me'), remote('movable.txt'));

        await sftp.moveFile(remote('movable.txt'), remote('moved.txt'));

        final names = (await sftp.listDirectory(remoteDir)).map((e) => e.name).toSet();
        expect(names, contains('moved.txt'));
        expect(names, isNot(contains('movable.txt')));
      });
    });

    group('permissions & metadata', () {
      test('changes permissions and reflects them in the listing', () async {
        await sftp.uploadFile(localFile('perm.txt', text: 'p'), remote('perm.txt'));

        await sftp.changePermissions(remote('perm.txt'), '600');

        // The SFTP `longname` (ls -l style) is portable across GNU/BusyBox.
        final entry = (await sftp.listDirectory(remoteDir)).firstWhere((e) => e.name == 'perm.txt');
        expect(entry.permissions, '-rw-------');
      });

      test('reads file details (type and size)', () async {
        await sftp.uploadFile(localFile('details.txt', text: 'detail-body'), remote('details.txt'));

        final details = await sftp.getFileDetails(remote('details.txt'));
        expect(details.size, '11');
        expect(details.fileType, isNotNull);
      });

      test('changes ownership (requires root)', () async {
        await sftp.uploadFile(localFile('owned.txt', text: 'o'), remote('owned.txt'));

        // chown to the connecting user:group should be a no-op that still succeeds.
        await sftp.changeOwner(remote('owned.txt'), user!, user!, recursive: false);
      }, skip: isRoot ? null : 'set SSH_IT_ROOT=true to run the chown test');
    });
  }, skip: skipReason);
}
