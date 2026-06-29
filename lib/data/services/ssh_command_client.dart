import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Narrow abstraction over the SSH command-execution surface the app needs.
///
/// Production code talks to this interface instead of dartssh2's [SSHClient]
/// directly, so tests can substitute an in-memory implementation. See
/// [DartSshCommandClient] for the real adapter.
abstract interface class SshCommandClient {
  /// Runs [command] on the remote host and returns its raw stdout bytes.
  Future<Uint8List> run(String command);

  /// Whether the underlying connection has been closed.
  bool get isClosed;

  /// Closes the underlying connection.
  void close();
}

/// Real [SshCommandClient] backed by a dartssh2 [SSHClient].
class DartSshCommandClient implements SshCommandClient {
  final SSHClient client;

  DartSshCommandClient(this.client);

  @override
  Future<Uint8List> run(String command) => client.run(command);

  @override
  bool get isClosed => client.isClosed;

  @override
  void close() => client.close();
}
