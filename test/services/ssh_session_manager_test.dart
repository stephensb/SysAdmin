import 'package:flutter_test/flutter_test.dart';
import 'package:sysadmin/data/services/ssh_session_manager.dart';

import '../utils/in_memory_ssh.dart';

void main() {
  group('SSHSessionManager', () {
    test('returns empty string when no client is set', () async {
      final manager = SSHSessionManager();
      expect(await manager.execute('whoami'), '');
    });

    test('executes a command and returns its output', () async {
      final host = InMemorySshHost();
      final manager = SSHSessionManager()..setClient(host.commandClient());

      final result = await manager.execute('echo "PING"');

      expect(result.trim(), 'PING');
    });

    test('runs queued commands sequentially in order', () async {
      final host = InMemorySshHost();
      final manager = SSHSessionManager()..setClient(host.commandClient());

      final results = await Future.wait([
        manager.execute('echo "a"'),
        manager.execute('echo "b"'),
        manager.execute('echo "c"'),
      ]);

      expect(results.map((r) => r.trim()).toList(), ['a', 'b', 'c']);
      expect(host.executedCommands, ['echo "a"', 'echo "b"', 'echo "c"']);
    });

    test('reports connection state from the client', () async {
      final host = InMemorySshHost();
      final manager = SSHSessionManager()..setClient(host.commandClient());

      expect(manager.isConnected, isTrue);

      host.closed = true; // simulate a dropped connection
      expect(manager.isConnected, isFalse);
    });
  });
}
