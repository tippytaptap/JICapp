import 'package:flutter_test/flutter_test.dart';
import 'package:community_app/core/fees.dart';

void main() {
  test('fee input converts decimal amounts to exact integer pence', () {
    expect(parseFeeMinor('0.01'), 1);
    expect(parseFeeMinor('0.29'), 29);
    expect(parseFeeMinor('12.5'), 1250);
    expect(parseFeeMinor('123456.78'), 12345678);
    expect(parseFeeMinor('1000000.00'), 100000000);
    expect(parseFeeMinor('1000000.01'), isNull);
  });
  test('fee input rejects ambiguous and nonpositive amounts', () {
    for (final value in [
      '0',
      '-2',
      '1,000',
      '1e4',
      '.50',
      '2.999',
      'NaN',
      '',
    ]) {
      expect(parseFeeMinor(value), isNull, reason: value);
    }
    expect(parseFeeMinor('1250', decimal: false), 1250);
    expect(parseFeeMinor('12.50', decimal: false), isNull);
  });
  test(
    'formatting preserves pence and does not assume unknown currency precision',
    () {
      expect(formatFeeAmount(1250, 'GBP'), '£12.50');
      expect(formatFeeAmount(-1250, 'GBP'), '−£12.50');
      expect(formatFeeAmount(1250, 'JPY'), '1250 minor units (JPY)');
      expect(feeInputAmount(29, 'GBP'), '0.29');
    },
  );
  test('payment attempt IDs are distinct RFC4122 version 4 UUIDs', () {
    final ids = List.generate(100, (_) => feeAttemptId());
    expect(ids.toSet().length, 100);
    for (final id in ids) {
      expect(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(id),
        isTrue,
      );
    }
  });
}
