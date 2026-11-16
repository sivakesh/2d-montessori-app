/// Rupee amounts in figures and in words, Indian style (lakh and crore),
/// both from the same whole number of paise, so they always agree.
abstract final class IndianAmount {
  /// [amount] (rupees) as a whole number of paise, exactly as recorded
  /// (rounded to the paisa, as every fee amount is stored and compared).
  static int paiseOf(double amount) {
    if (!amount.isFinite || amount < 0) throw ArgumentError.value(amount, 'amount', 'must be a finite amount of 0 or more');
    return (amount * 100).round();
  }

  /// "52,500.00", "1,25,000.50", "12,34,56,789.00": Indian digit grouping,
  /// always with paise.
  static String figures(int paise) {
    final rupees = (paise ~/ 100).toString();
    final p = (paise % 100).toString().padLeft(2, '0');
    if (rupees.length <= 3) return '$rupees.$p';
    final last3 = rupees.substring(rupees.length - 3);
    var rest = rupees.substring(0, rupees.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    return '${groups.join(',')},$last3.$p';
  }

  static const _ones = [
    'Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
    'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
  ];
  static const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

  /// 1–99: "Seven", "Nineteen", "Fifty-Two".
  static String _belowHundred(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 == 0 ? '' : '-${_ones[n % 10]}'}';

  /// 1–999: "Five Hundred Twenty-Two".
  static String _belowThousand(int n) => [
        if (n >= 100) '${_ones[n ~/ 100]} Hundred',
        if (n % 100 != 0) _belowHundred(n % 100),
      ].join(' ');

  /// A whole number in words, Indian style: "Fifty-Two Thousand Five
  /// Hundred", "Twelve Lakh", "One Hundred Twenty-Three Crore". 0 is
  /// "Zero". Above 99 crore the crores are themselves in words.
  static String number(int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'must be 0 or more');
    if (n == 0) return 'Zero';
    final parts = <String>[
      if (n >= 10000000) '${number(n ~/ 10000000)} Crore',
      if ((n ~/ 100000) % 100 != 0) '${_belowHundred((n ~/ 100000) % 100)} Lakh',
      if ((n ~/ 1000) % 100 != 0) '${_belowHundred((n ~/ 1000) % 100)} Thousand',
      if (n % 1000 != 0) _belowThousand(n % 1000),
    ];
    return parts.join(' ');
  }

  /// "Rupees Fifty-Two Thousand Five Hundred Only", "Rupees One Thousand
  /// Two Hundred Fifty and Fifty Paise Only", "Rupees Zero Only".
  static String words(int paise) {
    if (paise < 0) throw ArgumentError.value(paise, 'paise', 'must be 0 or more');
    final rupees = paise ~/ 100, p = paise % 100;
    return 'Rupees ${number(rupees)}${p == 0 ? '' : ' and ${_belowHundred(p)} Paise'} Only';
  }
}
