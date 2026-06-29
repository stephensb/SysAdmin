import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sysadmin/core/utils/util.dart';
import 'package:sysadmin/core/widgets/ios_scaffold.dart';
import 'package:sysadmin/data/models/port_forward.dart';
import 'package:sysadmin/data/models/ssh_connection.dart';
import 'package:sysadmin/data/services/port_forward_service.dart';

class PortForwardScreen extends StatefulWidget {
  final SSHConnection connection;

  const PortForwardScreen({super.key, required this.connection});

  @override
  State<PortForwardScreen> createState() => _PortForwardScreenState();
}

class _PortForwardScreenState extends State<PortForwardScreen> {
  final TextEditingController _localPortController = TextEditingController();
  final TextEditingController _remoteHostController =
      TextEditingController(text: '127.0.0.1');
  final TextEditingController _remotePortController = TextEditingController();

  final List<PortForwardService> _tunnels = [];
  bool _isStarting = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final tunnel in _tunnels) {
      tunnel.stop();
    }
    _localPortController.dispose();
    _remoteHostController.dispose();
    _remotePortController.dispose();
    super.dispose();
  }

  Future<void> _startTunnel() async {
    final localPort = int.tryParse(_localPortController.text);
    final remotePort = int.tryParse(_remotePortController.text);
    final remoteHost = _remoteHostController.text.trim();

    if (localPort == null || localPort < 1 || localPort > 65535) {
      setState(() => _errorMessage = 'Enter a valid local port (1-65535).');
      return;
    }
    if (remoteHost.isEmpty) {
      setState(() => _errorMessage = 'Enter a remote host.');
      return;
    }
    if (remotePort == null || remotePort < 1 || remotePort > 65535) {
      setState(() => _errorMessage = 'Enter a valid remote port (1-65535).');
      return;
    }
    if (_tunnels.any((t) => t.rule.localPort == localPort)) {
      setState(() => _errorMessage = 'Local port $localPort is already forwarded.');
      return;
    }

    final service = PortForwardService(
      connection: widget.connection,
      rule: PortForwardRule(
        localPort: localPort,
        remoteHost: remoteHost,
        remotePort: remotePort,
      ),
    );

    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });

    try {
      await service.start();
      setState(() {
        _tunnels.add(service);
        _localPortController.clear();
        _remotePortController.clear();
      });
      if (mounted) {
        Util.showMsg(context: context, msg: 'Forwarding ${service.rule.description}', bgColour: Colors.green);
      }
    }
    catch (e) {
      setState(() => _errorMessage = service.errorMessage ?? 'Failed to start: $e');
    }
    finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _stopTunnel(PortForwardService tunnel) async {
    await tunnel.stop();
    setState(() => _tunnels.remove(tunnel));
    if (mounted) {
      Util.showMsg(context: context, msg: 'Stopped ${tunnel.rule.description}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IosScaffold(
      title: 'Port Forwarding',
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Local forwarding (-L) via ${widget.connection.name}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),

              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade900)),
                ),

              TextField(
                controller: _localPortController,
                keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                maxLength: 5,
                decoration: InputDecoration(
                  labelText: 'Local Port',
                  counterText: '',
                  helperText: 'Port opened on this device (127.0.0.1)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 15),

              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _remoteHostController,
                      keyboardType: TextInputType.name,
                      decoration: InputDecoration(
                        labelText: 'Remote Host',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(':', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  ),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _remotePortController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                      maxLength: 5,
                      decoration: InputDecoration(
                        labelText: 'Port',
                        counterText: '',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: _isStarting ? null : _startTunnel,
                  child: _isStarting
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: theme.colorScheme.surface),
                            const SizedBox(width: 8),
                            const Text('Starting...'),
                          ],
                        )
                      : const Text('Start Forwarding'),
                ),
              ),

              const SizedBox(height: 24),

              Text('Active Tunnels', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),

              if (_tunnels.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No active tunnels.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ..._tunnels.map(
                  (tunnel) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(
                        tunnel.status == PortForwardStatus.error ? Icons.error_outline : Icons.swap_horiz,
                        color: tunnel.status == PortForwardStatus.error
                            ? theme.colorScheme.error
                            : Colors.green,
                      ),
                      title: Text(tunnel.rule.description),
                      subtitle: Text(
                        tunnel.errorMessage ?? tunnel.status.name,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.stop_circle_outlined, color: theme.colorScheme.error),
                        tooltip: 'Stop',
                        onPressed: () => _stopTunnel(tunnel),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
