import 'package:flutter_test/flutter_test.dart';
import 'package:propestindo_teknisi/data/app_update.dart';

void main() {
  test('isNewer membandingkan versi rilis dengan versi aplikasi', () {
    expect(isNewer('v1.2.0', '1.1.9'), isTrue);
    expect(isNewer('v1.2.0', '1.2.0'), isFalse);
    expect(isNewer('v1.10.0', '1.9.3'), isTrue);
    expect(isNewer('v1.0.0', '1.0.1'), isFalse);
    expect(isNewer('v2.0.0-rc.1', '1.9.0'), isTrue);
  });
}
