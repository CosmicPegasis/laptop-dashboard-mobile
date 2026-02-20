import 'package:flutter_test/flutter_test.dart';
import 'package:laptop_dashboard_mobile/models/file_info.dart';

void main() {
  group('FileInfo', () {
    group('constructor', () {
      test('creates object with valid values', () {
        final file = FileInfo(
          name: 'test.txt',
          size: 1024,
          modTime: 1704067200.0,
        );

        expect(file.name, 'test.txt');
        expect(file.size, 1024);
        expect(file.modTime, 1704067200.0);
      });
    });

    group('fromJson', () {
      test('parses valid JSON correctly', () {
        final file = FileInfo.fromJson({
          'name': 'document.pdf',
          'size': 2048,
          'mod_time': 1704067200.0,
        });

        expect(file.name, 'document.pdf');
        expect(file.size, 2048);
        expect(file.modTime, 1704067200.0);
      });

      test('handles null name with default', () {
        final file = FileInfo.fromJson({
          'name': null,
          'size': 1024,
          'mod_time': 1704067200.0,
        });

        expect(file.name, '');
      });

      test('handles missing name', () {
        final file = FileInfo.fromJson({
          'size': 1024,
          'mod_time': 1704067200.0,
        });

        expect(file.name, '');
      });

      test('handles different size types', () {
        expect(
          FileInfo.fromJson({'name': 'a', 'size': 100, 'mod_time': 0}).size,
          100,
        );
        expect(
          FileInfo.fromJson({'name': 'a', 'size': 100.5, 'mod_time': 0}).size,
          100,
        );
        expect(
          FileInfo.fromJson({'name': 'a', 'size': '2048', 'mod_time': 0}).size,
          2048,
        );
        expect(
          FileInfo.fromJson({
            'name': 'a',
            'size': 'invalid',
            'mod_time': 0,
          }).size,
          0,
        );
      });

      test('handles different modTime types', () {
        expect(
          FileInfo.fromJson({
            'name': 'a',
            'size': 0,
            'mod_time': 1704067200,
          }).modTime,
          1704067200.0,
        );
        expect(
          FileInfo.fromJson({
            'name': 'a',
            'size': 0,
            'mod_time': 1704067200.0,
          }).modTime,
          1704067200.0,
        );
        expect(
          FileInfo.fromJson({
            'name': 'a',
            'size': 0,
            'mod_time': '1704067200.5',
          }).modTime,
          1704067200.5,
        );
      });

      test('handles edge case modTime values', () {
        expect(
          FileInfo.fromJson({
            'name': 'a',
            'size': 0,
            'mod_time': double.nan,
          }).modTime,
          0.0,
        );
        expect(
          FileInfo.fromJson({
            'name': 'a',
            'size': 0,
            'mod_time': double.infinity,
          }).modTime,
          0.0,
        );
        expect(
          FileInfo.fromJson({'name': 'a', 'size': 0, 'mod_time': null}).modTime,
          0.0,
        );
        expect(
          FileInfo.fromJson({
            'name': 'a',
            'size': 0,
            'mod_time': 'invalid',
          }).modTime,
          0.0,
        );
      });
    });

    group('sizeReadable', () {
      test('formats bytes correctly', () {
        final file = FileInfo(name: 'a', size: 500, modTime: 0);
        expect(file.sizeReadable, '500 B');
      });

      test('formats kilobytes correctly', () {
        final file = FileInfo(name: 'a', size: 1024, modTime: 0);
        expect(file.sizeReadable, '1.0 KB');

        final file2 = FileInfo(name: 'a', size: 1536, modTime: 0);
        expect(file2.sizeReadable, '1.5 KB');

        final file3 = FileInfo(name: 'a', size: 10240, modTime: 0);
        expect(file3.sizeReadable, '10.0 KB');
      });

      test('formats megabytes correctly', () {
        final file = FileInfo(name: 'a', size: 1024 * 1024, modTime: 0);
        expect(file.sizeReadable, '1.0 MB');

        final file2 = FileInfo(
          name: 'a',
          size: (1024 * 1024 * 5.5).toInt(),
          modTime: 0,
        );
        expect(file2.sizeReadable, '5.5 MB');
      });

      test('formats gigabytes correctly', () {
        final file = FileInfo(name: 'a', size: 1024 * 1024 * 1024, modTime: 0);
        expect(file.sizeReadable, '1.0 GB');

        final file2 = FileInfo(
          name: 'a',
          size: (1024 * 1024 * 1024 * 2.75).toInt(),
          modTime: 0,
        );
        expect(file2.sizeReadable, '2.8 GB');
      });
    });

    group('modificationDate', () {
      test('converts epoch timestamp to DateTime', () {
        final file = FileInfo(name: 'a', size: 0, modTime: 1704067200.0);
        final date = file.modificationDate;

        expect(date.year, 2024);
        expect(date.month, 1);
        expect(date.day, 1);
      });

      test('handles fractional timestamps', () {
        final file = FileInfo(name: 'a', size: 0, modTime: 1704067200.5);
        final date = file.modificationDate;

        expect(date.millisecondsSinceEpoch, 1704067200500);
      });
    });

    group('toString', () {
      test('returns formatted string', () {
        final file = FileInfo(name: 'test.txt', size: 1024, modTime: 0);
        expect(file.toString(), 'FileInfo(name: test.txt, size: 1.0 KB)');
      });

      test('uses sizeReadable in output', () {
        final file = FileInfo(
          name: 'doc.pdf',
          size: 5 * 1024 * 1024,
          modTime: 0,
        );
        expect(file.toString(), 'FileInfo(name: doc.pdf, size: 5.0 MB)');
      });
    });
  });
}
