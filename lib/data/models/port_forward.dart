/// Describes a local (`-L`) SSH port-forwarding rule:
/// traffic arriving on [localHost]:[localPort] is tunnelled through the SSH
/// connection to [remoteHost]:[remotePort] (resolved from the server's side).
class PortForwardRule {
  final String localHost;
  final int localPort;
  final String remoteHost;
  final int remotePort;

  const PortForwardRule({
    this.localHost = '127.0.0.1',
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
  });

  String get description => '$localHost:$localPort → $remoteHost:$remotePort';

  Map<String, dynamic> toJson() => {
        'localHost': localHost,
        'localPort': localPort.toString(),
        'remoteHost': remoteHost,
        'remotePort': remotePort.toString(),
      };

  static PortForwardRule fromJson(Map<String, dynamic> json) => PortForwardRule(
        localHost: json['localHost'] ?? '127.0.0.1',
        localPort: int.parse(json['localPort'] ?? '0'),
        remoteHost: json['remoteHost'] ?? '',
        remotePort: int.parse(json['remotePort'] ?? '0'),
      );

  @override
  bool operator ==(Object other) =>
      other is PortForwardRule &&
      other.localHost == localHost &&
      other.localPort == localPort &&
      other.remoteHost == remoteHost &&
      other.remotePort == remotePort;

  @override
  int get hashCode => Object.hash(localHost, localPort, remoteHost, remotePort);
}
