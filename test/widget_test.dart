import 'package:erbakanmtal/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sekmeler okul sitesini gösteriyor', () {
    expect(sekmeler.length, 4);
    for (final s in sekmeler) {
      expect(Uri.parse(s.url).host, siteHost);
    }
  });
}
