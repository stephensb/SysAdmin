import 'package:flutter_test/flutter_test.dart';
import 'package:sysadmin/data/models/port_forward.dart';

void main() {
  group('PortForwardRule', () {
    test('defaults the local host to loopback', () {
      const rule = PortForwardRule(localPort: 8080, remoteHost: 'db', remotePort: 5432);
      expect(rule.localHost, '127.0.0.1');
    });

    test('describes the tunnel direction', () {
      const rule = PortForwardRule(localPort: 8080, remoteHost: 'db.internal', remotePort: 5432);
      expect(rule.description, '127.0.0.1:8080 → db.internal:5432');
    });

    test('round-trips through JSON', () {
      const rule = PortForwardRule(
        localHost: '0.0.0.0',
        localPort: 9000,
        remoteHost: '10.0.0.5',
        remotePort: 80,
      );

      final restored = PortForwardRule.fromJson(rule.toJson());

      expect(restored, rule);
      expect(restored.localHost, '0.0.0.0');
      expect(restored.remotePort, 80);
    });
  });
}
