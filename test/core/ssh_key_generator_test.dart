import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysadmin/core/utils/ssh_key_generator.dart';

void main() {
  group('SshKeyGenerator', () {
    test('generates a parseable RSA key pair with an OpenSSH public key', () async {
      final key = await SshKeyGenerator.generateRsaKey(bits: 2048, comment: 'tester@host');

      // Private key is PEM the import flow already accepts.
      expect(key.privateKeyPem, contains('BEGIN RSA PRIVATE KEY'));
      expect(key.privateKeyPem, contains('END RSA PRIVATE KEY'));

      // Public key is OpenSSH wire format with the requested comment.
      expect(key.publicKeyOpenSsh, startsWith('ssh-rsa '));
      expect(key.publicKeyOpenSsh, endsWith(' tester@host'));

      // dartssh2 must be able to parse what we generated (this is exactly what
      // the connection flow does with the private key).
      expect(() => SSHKeyPair.fromPem(key.privateKeyPem), returnsNormally);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('omits the trailing comment when none is given', () async {
      final key = await SshKeyGenerator.generateRsaKey(bits: 2048);
      expect(key.publicKeyOpenSsh, startsWith('ssh-rsa '));
      expect(key.publicKeyOpenSsh.trim().split(' ').length, 2);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
