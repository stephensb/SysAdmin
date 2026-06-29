import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// Result of generating an SSH key pair.
class GeneratedSshKey {
  /// PEM-encoded private key (`-----BEGIN RSA PRIVATE KEY-----`).
  /// This format is accepted by the existing import flow and `SSHKeyPair.fromPem`.
  final String privateKeyPem;

  /// OpenSSH formatted public key, e.g. `ssh-rsa AAAAB3Nz... user@host`.
  /// Install this in the server's `~/.ssh/authorized_keys`.
  final String publicKeyOpenSsh;

  const GeneratedSshKey({
    required this.privateKeyPem,
    required this.publicKeyOpenSsh,
  });
}

/// Generates SSH key pairs locally on the device.
///
/// dartssh2 can only parse keys (`SSHKeyPair.fromPem`), not generate them, so
/// generation is done with pointycastle (via basic_utils) and the OpenSSH
/// public-key wire format is encoded by hand.
class SshKeyGenerator {
  /// Generates an RSA key pair of [bits] size (2048 / 3072 / 4096).
  ///
  /// The key generation runs on a background isolate to keep the UI responsive.
  /// [comment] is appended to the OpenSSH public key (commonly `user@host`).
  static Future<GeneratedSshKey> generateRsaKey({
    int bits = 4096,
    String comment = '',
  }) async {
    // Heavy CPU work -> run off the UI isolate.
    final parts = await compute(_generateRsaParts, bits);

    final trimmedComment = comment.trim();
    final publicKey = trimmedComment.isEmpty
        ? 'ssh-rsa ${parts.publicKeyBlobBase64}'
        : 'ssh-rsa ${parts.publicKeyBlobBase64} $trimmedComment';

    return GeneratedSshKey(
      privateKeyPem: parts.privateKeyPem,
      publicKeyOpenSsh: publicKey,
    );
  }
}

/// Isolate-friendly container for the values produced during key generation.
class _RsaKeyParts {
  final String privateKeyPem;
  final String publicKeyBlobBase64;

  const _RsaKeyParts(this.privateKeyPem, this.publicKeyBlobBase64);
}

/// Top-level function executed inside the isolate spawned by [compute].
_RsaKeyParts _generateRsaParts(int bits) {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: bits);
  final privateKey = pair.privateKey as RSAPrivateKey;
  final publicKey = pair.publicKey as RSAPublicKey;

  final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);

  // OpenSSH "ssh-rsa" public key blob:
  //   string  "ssh-rsa"
  //   mpint   e
  //   mpint   n
  final builder = BytesBuilder();
  _appendSshString(builder, Uint8List.fromList(utf8.encode('ssh-rsa')));
  _appendSshString(builder, _encodeMpint(publicKey.exponent!));
  _appendSshString(builder, _encodeMpint(publicKey.modulus!));

  return _RsaKeyParts(privateKeyPem, base64.encode(builder.toBytes()));
}

/// Writes an SSH `string`: a 4-byte big-endian length prefix followed by [data].
void _appendSshString(BytesBuilder builder, Uint8List data) {
  final length = ByteData(4)..setUint32(0, data.length, Endian.big);
  builder.add(length.buffer.asUint8List());
  builder.add(data);
}

/// Encodes a positive [BigInt] as an SSH `mpint` payload: big-endian bytes with
/// a leading `0x00` when the most-significant bit is set (so it stays positive).
Uint8List _encodeMpint(BigInt value) {
  var bytes = _bigIntToBytes(value);
  if (bytes.isNotEmpty && (bytes.first & 0x80) != 0) {
    final padded = Uint8List(bytes.length + 1);
    padded.setRange(1, padded.length, bytes);
    bytes = padded;
  }
  return bytes;
}

/// Converts a non-negative [BigInt] to its minimal big-endian byte array.
Uint8List _bigIntToBytes(BigInt value) {
  if (value == BigInt.zero) return Uint8List.fromList([0]);

  final bytes = <int>[];
  var current = value;
  final mask = BigInt.from(0xff);
  while (current > BigInt.zero) {
    bytes.add((current & mask).toInt());
    current = current >> 8;
  }
  return Uint8List.fromList(bytes.reversed.toList());
}
