import 'dart:math';

int? parseFeeMinor(String input, {bool decimal = true}) {
  final value = input.trim();
  if (decimal) {
    if (!RegExp(r'^\d{1,7}(?:\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final minor =
        int.parse(parts[0]) * 100 +
        (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
    return minor >= 1 && minor <= 100000000 ? minor : null;
  }
  if (!RegExp(r'^\d{1,9}$').hasMatch(value)) return null;
  final minor = int.parse(value);
  return minor >= 1 && minor <= 100000000 ? minor : null;
}

bool hasDecimalFeeCurrency(String currency) =>
    const {'GBP', 'EUR', 'USD'}.contains(currency);

String formatFeeAmount(int minor, String currency) {
  if (!hasDecimalFeeCurrency(currency)) return '$minor minor units ($currency)';
  final sign = minor < 0 ? '−' : '';
  final symbol = {'GBP': '£', 'EUR': '€', 'USD': r'$'}[currency]!;
  final amount = minor.abs();
  return '$sign$symbol${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';
}

String feeInputAmount(int minor, String currency) =>
    hasDecimalFeeCurrency(currency)
    ? '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}'
    : '$minor';

String feeAttemptId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
