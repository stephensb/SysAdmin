import 'package:flutter_test/flutter_test.dart';
import 'package:sysadmin/data/models/file_details.dart';
import 'package:sysadmin/data/models/remote_file.dart';
import 'package:sysadmin/data/models/sftp_permission_models.dart';

void main() {
  group('UnixUser.fromString', () {
    test('parses a passwd line', () {
      final user = UnixUser.fromString('user:x:1000:1000:User:/home/user:/bin/bash');
      expect(user.name, 'user');
      expect(user.uid, '1000');
    });

    test('throws on a malformed line', () {
      expect(() => UnixUser.fromString('bad'), throwsFormatException);
    });
  });

  group('UnixGroup.fromString', () {
    test('parses a group line', () {
      final group = UnixGroup.fromString('sudo:x:27:user');
      expect(group.name, 'sudo');
      expect(group.gid, '27');
    });

    test('throws on a malformed line', () {
      expect(() => UnixGroup.fromString('bad'), throwsFormatException);
    });
  });

  group('FilePermission', () {
    test('round-trips an ls-style string', () {
      const raw = '-rwxr-xr--';
      final perm = FilePermission.fromString(raw);
      expect(perm.type, '-');
      expect(perm.ownerRead, isTrue);
      expect(perm.ownerWrite, isTrue);
      expect(perm.ownerExecute, isTrue);
      expect(perm.groupWrite, isFalse);
      expect(perm.otherExecute, isFalse);
      expect(perm.toString(), raw);
    });

    test('rejects a wrong-length string', () {
      expect(() => FilePermission.fromString('-rw'), throwsFormatException);
    });
  });

  group('FileDetails.fromCommandOutputs', () {
    test('parses size, permission, uid and gid from stat output', () {
      const statOutput = '  File: notes.txt\n'
          '  Size: 1234            Blocks: 8          IO Block: 4096   regular file\n'
          'Device: 801h/2049d      Inode: 98765       Links: 1\n'
          'Access: (0644/-rw-r--r--)  Uid: ( 1000/    user)   Gid: ( 1000/    user)\n'
          'Access: 2024-01-01 12:00:00.000000000 +0000\n'
          'Modify: 2024-01-02 12:00:00.000000000 +0000\n'
          'Change: 2024-01-03 12:00:00.000000000 +0000\n';

      final details = FileDetails.fromCommandOutputs(
        path: '/home/user/notes.txt',
        fileOutput: '/home/user/notes.txt: ASCII text',
        statOutput: statOutput,
      );

      expect(details.size, '1234');
      expect(details.blocks, '8');
      expect(details.inode, '98765');
      expect(details.accessPermission, '(0644/-rw-r--r--)');
      expect(details.uid, contains('1000'));
      expect(details.gid, contains('1000'));
      expect(details.fileType, 'ASCII text');
    });
  });

  group('RemoteFile display helpers', () {
    test('formats file size in human units', () {
      const file = RemoteFile(
        name: 'a.bin',
        path: '/a.bin',
        type: FileType.file,
        permissions: '-rw-r--r--',
        size: 2048,
      );
      expect(file.isDirectory, isFalse);
      expect(file.formattedSize, '2.0 KB');
    });

    test('reports directories distinctly', () {
      const dir = RemoteFile(
        name: 'etc',
        path: '/etc',
        type: FileType.directory,
        permissions: 'drwxr-xr-x',
        size: 0,
      );
      expect(dir.isDirectory, isTrue);
      expect(dir.formattedSize, 'directory');
    });
  });
}
