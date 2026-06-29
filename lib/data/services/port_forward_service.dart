import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models/port_forward.dart';
import '../models/ssh_connection.dart';

enum PortForwardStatus { stopped, starting, running, error }

/// Manages a single local (`-L`) SSH port-forwarding tunnel.
///
/// Each tunnel owns a dedicated [SSHClient] so its lifecycle is independent of
/// the shared client used elsewhere (e.g. terminal / SFTP). When [start] is
/// called it binds a local [ServerSocket] and, for every accepted connection,
/// opens a `direct-tcpip` channel via [SSHClient.forwardLocal] and pipes the
/// two streams together.
class PortForwardService {
  final SSHConnection connection;
  final PortForwardRule rule;

  SSHClient? _client;
  ServerSocket? _server;
  final List<Socket> _sockets = [];

  PortForwardStatus status = PortForwardStatus.stopped;
  String? errorMessage;

  PortForwardService({required this.connection, required this.rule});

  bool get isRunning => status == PortForwardStatus.running;

  Future<void> start() async {
    if (status == PortForwardStatus.running || status == PortForwardStatus.starting) {
      return;
    }

    status = PortForwardStatus.starting;
    errorMessage = null;

    try {
      _client = SSHClient(
        await SSHSocket.connect(
          connection.host,
          connection.port,
          timeout: const Duration(seconds: 10),
        ),
        username: connection.username,
        onPasswordRequest: () => connection.password ?? '',
        identities: connection.privateKey != null
            ? SSHKeyPair.fromPem(connection.privateKey!)
            : null,
      );

      // Make sure authentication succeeds before binding the local port.
      await _client!.authenticated;

      _server = await ServerSocket.bind(rule.localHost, rule.localPort);
      _server!.listen(
        _handleConnection,
        onError: (Object e) {
          errorMessage = 'Local socket error: $e';
          status = PortForwardStatus.error;
        },
      );

      status = PortForwardStatus.running;
    }
    on SocketException catch (e) {
      status = PortForwardStatus.error;
      if (e.osError?.errorCode == 98 || e.message.contains('in use')) {
        errorMessage = 'Local port ${rule.localPort} is already in use.';
      } else {
        errorMessage = 'Network error: ${e.message}';
      }
      await stop();
      rethrow;
    }
    catch (e) {
      status = PortForwardStatus.error;
      errorMessage = 'Failed to start forwarding: $e';
      await stop();
      rethrow;
    }
  }

  Future<void> _handleConnection(Socket socket) async {
    _sockets.add(socket);
    try {
      final forward = await _client!.forwardLocal(rule.remoteHost, rule.remotePort);

      // Local -> remote
      socket.cast<List<int>>().listen(
            forward.sink.add,
            onDone: () => forward.sink.close(),
            onError: (_) => forward.sink.close(),
            cancelOnError: true,
          );

      // Remote -> local
      forward.stream.listen(
        (data) => socket.add(data),
        onDone: () => _closeSocket(socket),
        onError: (_) => _closeSocket(socket),
        cancelOnError: true,
      );
    }
    catch (e) {
      debugPrint('Port forward channel error: $e');
      _closeSocket(socket);
    }
  }

  void _closeSocket(Socket socket) {
    try {
      socket.destroy();
    } catch (_) {/* already closed */}
    _sockets.remove(socket);
  }

  Future<void> stop() async {
    for (final socket in List<Socket>.from(_sockets)) {
      _closeSocket(socket);
    }
    _sockets.clear();

    await _server?.close();
    _server = null;

    _client?.close();
    _client = null;

    if (status != PortForwardStatus.error) {
      status = PortForwardStatus.stopped;
    }
  }
}
