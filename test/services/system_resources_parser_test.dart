import 'package:flutter_test/flutter_test.dart';
import 'package:sysadmin/data/services/system_resources_parser.dart';

void main() {
  group('SystemResourcesParser.parseCpuCount', () {
    test('parses a core count', () {
      expect(SystemResourcesParser.parseCpuCount('8\n'), 8);
    });

    test('defaults to 1 on garbage', () {
      expect(SystemResourcesParser.parseCpuCount('oops'), 1);
    });
  });

  group('SystemResourcesParser.parseCpuUsage', () {
    test('returns 0 on the first sample (baseline only)', () {
      final parser = SystemResourcesParser();
      expect(parser.parseCpuUsage('cpu 100 0 100 700 0 0 0 0'), 0.0);
    });

    test('computes usage from the delta between two samples', () {
      final parser = SystemResourcesParser();
      parser.parseCpuUsage('cpu 100 0 100 700 0 0 0 0'); // baseline

      // busy +100 (user+50, system+50), idle +100 => 50% busy
      final usage = parser.parseCpuUsage('cpu 150 0 150 800 0 0 0 0');
      expect(usage, closeTo(50.0, 1e-9));
    });

    test('reset() clears the baseline', () {
      final parser = SystemResourcesParser();
      parser.parseCpuUsage('cpu 100 0 100 700 0 0 0 0');
      parser.reset();
      // No baseline again => 0.
      expect(parser.parseCpuUsage('cpu 150 0 150 800 0 0 0 0'), 0.0);
    });

    test('ignores malformed lines', () {
      final parser = SystemResourcesParser();
      expect(parser.parseCpuUsage(''), 0.0);
      expect(parser.parseCpuUsage('cpu 1 2'), 0.0);
    });
  });

  group('SystemResourcesParser.parseMemInfo', () {
    test('uses MemAvailable when present', () {
      final parser = SystemResourcesParser();
      const meminfo = 'MemTotal:       2048000 kB\n'
          'MemFree:         512000 kB\n'
          'MemAvailable:   1024000 kB\n'
          'SwapTotal:      1024000 kB\n'
          'SwapFree:        512000 kB\n';

      final mem = parser.parseMemInfo(meminfo);

      expect(mem.totalRam, closeTo(2000.0, 1e-9)); // MB
      expect(mem.usedRam, closeTo(1000.0, 1e-9));
      expect(mem.ramUsage, closeTo(50.0, 1e-9));
      expect(mem.totalSwap, closeTo(1000.0, 1e-9));
      expect(mem.usedSwap, closeTo(500.0, 1e-9));
      expect(mem.swapUsage, closeTo(50.0, 1e-9));
    });

    test('falls back to MemFree when MemAvailable is absent', () {
      final parser = SystemResourcesParser();
      const meminfo = 'MemTotal:       2048000 kB\n'
          'MemFree:         512000 kB\n';

      final mem = parser.parseMemInfo(meminfo);
      // used = total - free = 2000 - 500 = 1500
      expect(mem.usedRam, closeTo(1500.0, 1e-9));
      expect(mem.ramUsage, closeTo(75.0, 1e-9));
    });

    test('returns zeros for empty input', () {
      final mem = SystemResourcesParser().parseMemInfo('');
      expect(mem.totalRam, 0.0);
      expect(mem.ramUsage, 0.0);
      expect(mem.swapUsage, 0.0);
    });
  });
}
