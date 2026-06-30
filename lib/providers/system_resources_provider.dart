import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sysadmin/data/services/system_resources_parser.dart';
import 'package:sysadmin/providers/ssh_state.dart';

class SystemResources {
  final double cpuUsage;
  final double ramUsage;
  final double swapUsage;
  final double totalRam;  // in MB
  final double totalSwap; // in MB
  final double usedRam;   // in MB
  final double usedSwap;  // in MB
  final int cpuCount;     // Number of CPUs

  SystemResources({
    this.cpuUsage = 0.0,
    this.ramUsage = 0.0,
    this.swapUsage = 0.0,
    this.totalRam = 0.0,
    this.totalSwap = 0.0,
    this.usedRam = 0.0,
    this.usedSwap = 0.0,
    this.cpuCount = 0,
  });

  SystemResources copyWith({
    double? cpuUsage,
    double? ramUsage,
    double? swapUsage,
    double? totalRam,
    double? totalSwap,
    double? usedRam,
    double? usedSwap,
    int? cpuCount,
  }) {
    return SystemResources(
      cpuUsage: cpuUsage ?? this.cpuUsage,
      ramUsage: ramUsage ?? this.ramUsage,
      swapUsage: swapUsage ?? this.swapUsage,
      totalRam: totalRam ?? this.totalRam,
      totalSwap: totalSwap ?? this.totalSwap,
      usedRam: usedRam ?? this.usedRam,
      usedSwap: usedSwap ?? this.usedSwap,
      cpuCount: cpuCount ?? this.cpuCount,
    );
  }
}

class OptimizedSystemResourcesNotifier extends StateNotifier<SystemResources> {
  final Ref ref;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  // Pure parser holding the previous CPU sample for delta-based usage.
  final SystemResourcesParser _parser = SystemResourcesParser();

  OptimizedSystemResourcesNotifier(this.ref) : super(SystemResources()) {
    // Initial state is all zeros
  }

  void startMonitoring() {
    if (_refreshTimer != null) return;

    _refreshTimer = Timer.periodic(
        const Duration(seconds: 1),
            (_) async => await _fetchResourceUsage()
    );
  }

  void stopMonitoring() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _parser.reset();
    state = SystemResources(); // Reset to zeros
  }

  void resetValues() {
    // Reset all usage values while preserving system information
    state = SystemResources(
      cpuUsage: 0.0,
      ramUsage: 0.0,
      swapUsage: 0.0,
      usedRam: 0.0,
      usedSwap: 0.0,
      totalRam: state.totalRam,
      totalSwap: state.totalSwap,
      cpuCount: state.cpuCount,
    );
  }

  void restart() {
    stopMonitoring();
    resetValues();
    startMonitoring();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchResourceUsage() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final sessionManager = ref.read(sshSessionManagerProvider);

      // Fetch CPU count only once if we don't have it yet
      int cpuCount = state.cpuCount;
      if (cpuCount <= 1) {
        // Read directly from /proc/cpuinfo
        final cpuInfoResult = await sessionManager.execute('cat /proc/cpuinfo | grep -c processor');
        cpuCount = int.tryParse(cpuInfoResult.trim()) ?? 1;
      }

      // Read CPU stats directly from /proc/stat
      final cpuStatResult = await sessionManager.execute('cat /proc/stat | head -1');

      // Read memory info directly from /proc/meminfo
      final memInfoResult = await sessionManager.execute('cat /proc/meminfo');

      // Parse CPU usage (delta-based) and memory/swap usage.
      final cpuUsage = _parser.parseCpuUsage(cpuStatResult);
      final mem = _parser.parseMemInfo(memInfoResult);

      // Update state
      state = state.copyWith(
        cpuUsage: cpuUsage,
        ramUsage: mem.ramUsage,
        swapUsage: mem.swapUsage,
        totalRam: mem.totalRam,
        totalSwap: mem.totalSwap,
        usedRam: mem.usedRam,
        usedSwap: mem.usedSwap,
        cpuCount: cpuCount,
      );
    }
    catch (e) {
      debugPrint('Error fetching system resources: $e');
      // Do not update state on error to maintain previous values
    }
    finally {
      _isRefreshing = false;
    }
  }
}

final optimizedSystemResourcesProvider = StateNotifierProvider<OptimizedSystemResourcesNotifier, SystemResources>((ref) {
  return OptimizedSystemResourcesNotifier(ref);
});