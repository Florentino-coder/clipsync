import 'package:clipsync_app/withdraw/bank_logos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps known bank codes to asset paths', () {
    expect(bankLogoAsset('KBANK'), contains('kbank'));
    expect(bankLogoAsset('scb'), contains('scb'));
  });

  test('unknown bank uses generic', () {
    expect(bankLogoAsset('NOPE'), contains('generic'));
    expect(bankLogoAsset(''), contains('generic'));
  });
}
