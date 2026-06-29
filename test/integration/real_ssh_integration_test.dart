import 'dart:io';

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
/// `docker run -d -p 2222:22 -e USER_NAME=me -e USER_PASSWORD=secret lscr.io/linuxserver/openssh-server`
/// then set `SSH_IT_HOST=127.0.0.1 SSH_IT_PORT=2222`.
void main() {
  final env = Platform.environment;
  final host = env['SSH_IT_HOST'];
  final user = env['SSH_IT_USER'];
  final password = env['SSH_IT_PASS'];
  final port = int.tryParse(env['SSH_IT_PORT'] ?? '22') ?? 22;

  final skipReason = (host == null || user == null || password == null)
      ? 'set SSH_IT_HOST, SSH_IT_USER and SSH_IT_PASS to run this integration test'
      : null;

  group('real SSH connection', () {
    late SftpService sftp;
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('real_ssh_');
      sftp = SftpService();
      await sftp.connect(SSHConnection(
        name: 'integration',
        host: host!,
        port: port,
        username: user!,
        password: password,
      ));
    });

    tearDown(() async {
      await sftp.disconnect();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('runs a command (reads /etc/passwd)', () async {
      final users = await sftp.getUsers();
      expect(users, isNotEmpty);
      expect(users.map((u) => u.name), contains('root'));
    });

    test('round-trips a file via SFTP', () async {
      final remotePath = '/tmp/sysadmin_it_${DateTime.now().millisecondsSinceEpoch}.txt';
      final local = File('${tempDir.path}/payload.txt')..writeAsStringSync('hello-from-test');

      await sftp.uploadFile(local.path, remotePath);

      final outPath = '${tempDir.path}/roundtrip.txt';
      await sftp.downloadFile(remotePath: remotePath, localPath: outPath, onProgress: (_) {});

      expect(File(outPath).readAsStringSync(), 'hello-from-test');

      await sftp.deleteFile(remotePath);
    });
  }, skip: skipReason);
}
