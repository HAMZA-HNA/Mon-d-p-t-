import 'package:flutter_test/flutter_test.dart';
import 'package:orange_wifi_control/models/network_device.dart';

void main() {
  group('NetworkDevice.normalizeMac', () {
    test('normalise les séparateurs et la casse', () {
      expect(NetworkDevice.normalizeMac('aa-bb-cc-dd-ee-ff'),
          'AA:BB:CC:DD:EE:FF');
      expect(NetworkDevice.normalizeMac('AABBCCDDEEFF'), 'AA:BB:CC:DD:EE:FF');
      expect(NetworkDevice.normalizeMac('aa:bb:cc:dd:ee:ff'),
          'AA:BB:CC:DD:EE:FF');
    });

    test('laisse la valeur brute si longueur invalide', () {
      expect(NetworkDevice.normalizeMac('xyz'), 'XYZ');
    });
  });

  group('NetworkDevice.displayName', () {
    test('utilise le hostname quand présent', () {
      const d = NetworkDevice(mac: 'AA:BB:CC:DD:EE:FF', hostname: 'iPhone-Hamza');
      expect(d.displayName, 'iPhone-Hamza');
    });

    test('retombe sur la MAC si hostname vide ou inconnu', () {
      const d1 = NetworkDevice(mac: 'AA:BB:CC:DD:EE:FF', hostname: 'unknown');
      const d2 = NetworkDevice(mac: 'AA:BB:CC:DD:EE:FF');
      expect(d1.displayName, 'AA:BB:CC:DD:EE:FF');
      expect(d2.displayName, 'AA:BB:CC:DD:EE:FF');
    });
  });

  group('égalité par MAC', () {
    test('deux appareils avec la même MAC sont égaux', () {
      const a = NetworkDevice(mac: 'AA:BB:CC:DD:EE:FF', ip: '192.168.1.10');
      const b = NetworkDevice(mac: 'AA:BB:CC:DD:EE:FF', ip: '192.168.1.20');
      expect(a, equals(b));
    });
  });
}
