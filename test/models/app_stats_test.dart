import 'package:flutter_test/flutter_test.dart';
import 'package:laptop_dashboard_mobile/models/app_stats.dart';

void main() {
  group('AppStats', () {
    group('constructor', () {
      test('creates object with valid values', () {
        final stats = AppStats(
          cpu: 50.0,
          ram: 75.0,
          temp: 65.0,
          battery: 80.0,
          isPlugged: true,
        );

        expect(stats.cpu, 50.0);
        expect(stats.ram, 75.0);
        expect(stats.temp, 65.0);
        expect(stats.battery, 80.0);
        expect(stats.isPlugged, true);
      });
    });

    group('fromJson with numeric values', () {
      test('parses int values correctly', () {
        final stats = AppStats.fromJson({
          'cpu_usage': 50,
          'ram_usage': 75,
          'cpu_temp': 65,
          'battery_percent': 80,
          'is_plugged': 1,
        });

        expect(stats.cpu, 50.0);
        expect(stats.ram, 75.0);
        expect(stats.temp, 65.0);
        expect(stats.battery, 80.0);
        expect(stats.isPlugged, true);
      });

      test('parses double values correctly', () {
        final stats = AppStats.fromJson({
          'cpu_usage': 50.5,
          'ram_usage': 75.3,
          'cpu_temp': 65.7,
          'battery_percent': 80.1,
          'is_plugged': 0,
        });

        expect(stats.cpu, 50.5);
        expect(stats.ram, 75.3);
        expect(stats.temp, 65.7);
        expect(stats.battery, 80.1);
        expect(stats.isPlugged, false);
      });
    });

    group('fromJson with string values', () {
      test('parses string numbers correctly', () {
        final stats = AppStats.fromJson({
          'cpu_usage': '50.5',
          'ram_usage': '75.3',
          'cpu_temp': '65.7',
          'battery_percent': '80.1',
          'is_plugged': 'true',
        });

        expect(stats.cpu, 50.5);
        expect(stats.ram, 75.3);
        expect(stats.temp, 65.7);
        expect(stats.battery, 80.1);
        expect(stats.isPlugged, true);
      });

      test('handles invalid strings with defaults', () {
        final stats = AppStats.fromJson({
          'cpu_usage': 'invalid',
          'ram_usage': 'NaN',
          'cpu_temp': 'not a number',
          'battery_percent': '',
          'is_plugged': 'maybe',
        });

        expect(stats.cpu, 0.0);
        expect(stats.ram, 0.0);
        expect(stats.temp, 0.0);
        expect(stats.battery, 0.0);
        expect(stats.isPlugged, false);
      });
    });

    group('fromJson with edge case numeric values', () {
      test('handles NaN and Infinity', () {
        final stats = AppStats.fromJson({
          'cpu_usage': double.nan,
          'ram_usage': double.infinity,
          'cpu_temp': double.negativeInfinity,
          'battery_percent': 80.0,
          'is_plugged': true,
        });

        expect(stats.cpu, 0.0);
        expect(stats.ram, 0.0);
        expect(stats.temp, 0.0);
        expect(stats.battery, 80.0);
        expect(stats.isPlugged, true);
      });

      test('handles null values', () {
        final stats = AppStats.fromJson({
          'cpu_usage': null,
          'ram_usage': null,
          'cpu_temp': null,
          'battery_percent': null,
          'is_plugged': null,
        });

        expect(stats.cpu, 0.0);
        expect(stats.ram, 0.0);
        expect(stats.temp, 0.0);
        expect(stats.battery, 0.0);
        expect(stats.isPlugged, false);
      });
    });

    group('isPlugged parsing', () {
      test('parses boolean directly', () {
        expect(AppStats.fromJson({'is_plugged': true}).isPlugged, true);
        expect(AppStats.fromJson({'is_plugged': false}).isPlugged, false);
      });

      test('parses numeric as boolean', () {
        expect(AppStats.fromJson({'is_plugged': 0}).isPlugged, false);
        expect(AppStats.fromJson({'is_plugged': 1}).isPlugged, true);
        expect(AppStats.fromJson({'is_plugged': 100}).isPlugged, true);
      });

      test('parses string boolean values', () {
        expect(AppStats.fromJson({'is_plugged': 'true'}).isPlugged, true);
        expect(AppStats.fromJson({'is_plugged': 'false'}).isPlugged, false);
        expect(AppStats.fromJson({'is_plugged': '1'}).isPlugged, true);
        expect(AppStats.fromJson({'is_plugged': '0'}).isPlugged, false);
        expect(AppStats.fromJson({'is_plugged': 'yes'}).isPlugged, true);
        expect(AppStats.fromJson({'is_plugged': 'YES'}).isPlugged, true);
        expect(AppStats.fromJson({'is_plugged': 'no'}).isPlugged, false);
      });
    });
  });
}
