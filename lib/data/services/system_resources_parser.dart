/// Parsed memory/swap figures (all sizes in MB, usages in percent).
class MemorySnapshot {
  final double totalRam;
  final double usedRam;
  final double ramUsage;
  final double totalSwap;
  final double usedSwap;
  final double swapUsage;

  const MemorySnapshot({
    this.totalRam = 0.0,
    this.usedRam = 0.0,
    this.ramUsage = 0.0,
    this.totalSwap = 0.0,
    this.usedSwap = 0.0,
    this.swapUsage = 0.0,
  });
}

/// Pure parsing of Linux `/proc` resource files used by the system monitor.
///
/// Extracted from the resources provider so the CPU-delta math and `/proc`
/// parsing can be unit-tested without an SSH connection. CPU usage is
/// stateful (it needs the previous sample), so a single instance should be
/// reused across samples; call [reset] when monitoring stops.
class SystemResourcesParser {
  // Previous [user, nice, system, idle, iowait, irq, softirq, steal] sample.
  List<int>? _prevCpuStats;

  /// Parses the CPU core count from `cat /proc/cpuinfo | grep -c processor`.
  static int parseCpuCount(String output) => int.tryParse(output.trim()) ?? 1;

  /// Returns CPU usage percent from the first line of `/proc/stat`, comparing
  /// against the previously seen sample. The first call (or any call without a
  /// usable previous sample) returns 0 and just records the baseline.
  double parseCpuUsage(String procStatFirstLine) {
    if (procStatFirstLine.isEmpty) return 0.0;

    final parts = procStatFirstLine.trim().split(RegExp(r'\s+'));
    if (parts.length <= 4) return 0.0;

    final user = int.tryParse(parts[1]) ?? 0;
    final nice = int.tryParse(parts[2]) ?? 0;
    final system = int.tryParse(parts[3]) ?? 0;
    final idle = int.tryParse(parts[4]) ?? 0;
    final iowait = parts.length > 5 ? (int.tryParse(parts[5]) ?? 0) : 0;
    final irq = parts.length > 6 ? (int.tryParse(parts[6]) ?? 0) : 0;
    final softirq = parts.length > 7 ? (int.tryParse(parts[7]) ?? 0) : 0;
    final steal = parts.length > 8 ? (int.tryParse(parts[8]) ?? 0) : 0;

    final currentStats = [user, nice, system, idle, iowait, irq, softirq, steal];

    double cpuUsage = 0.0;
    if (_prevCpuStats != null) {
      int idleDelta = idle - _prevCpuStats![3];
      if (parts.length > 5) {
        idleDelta += iowait - _prevCpuStats![4];
      }

      int totalDelta = 0;
      for (int i = 0; i < currentStats.length; i++) {
        if (i < _prevCpuStats!.length) {
          totalDelta += currentStats[i] - _prevCpuStats![i];
        }
      }

      if (totalDelta > 0) {
        cpuUsage = 100.0 * (1.0 - idleDelta / totalDelta);
      }
    }

    _prevCpuStats = currentStats;
    return cpuUsage;
  }

  /// Parses `/proc/meminfo` contents into RAM/swap totals and usage.
  MemorySnapshot parseMemInfo(String procMeminfo) {
    if (procMeminfo.isEmpty) return const MemorySnapshot();

    double totalRam = 0.0, freeRam = 0.0, availableRam = 0.0;
    double totalSwap = 0.0, freeSwap = 0.0;

    for (final line in procMeminfo.split('\n')) {
      if (line.startsWith('MemTotal:')) {
        totalRam = _parseMemInfoValue(line) / 1024.0; // kB -> MB
      } else if (line.startsWith('MemFree:')) {
        freeRam = _parseMemInfoValue(line) / 1024.0;
      } else if (line.startsWith('MemAvailable:')) {
        availableRam = _parseMemInfoValue(line) / 1024.0;
      } else if (line.startsWith('SwapTotal:')) {
        totalSwap = _parseMemInfoValue(line) / 1024.0;
      } else if (line.startsWith('SwapFree:')) {
        freeSwap = _parseMemInfoValue(line) / 1024.0;
      }
    }

    // Prefer MemAvailable when present, else fall back to MemFree.
    final double usedRam = availableRam > 0 ? totalRam - availableRam : totalRam - freeRam;
    final double usedSwap = totalSwap - freeSwap;

    return MemorySnapshot(
      totalRam: totalRam,
      usedRam: usedRam,
      ramUsage: totalRam > 0 ? (usedRam / totalRam) * 100 : 0.0,
      totalSwap: totalSwap,
      usedSwap: usedSwap,
      swapUsage: totalSwap > 0 ? (usedSwap / totalSwap) * 100 : 0.0,
    );
  }

  /// Clears the CPU baseline so the next [parseCpuUsage] starts fresh.
  void reset() => _prevCpuStats = null;

  double _parseMemInfoValue(String line) {
    final match = RegExp(r':\s*(\d+)').firstMatch(line);
    if (match != null && match.group(1) != null) {
      return double.tryParse(match.group(1)!) ?? 0.0;
    }
    return 0.0;
  }
}
