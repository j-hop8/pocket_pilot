import 'package:intl/intl.dart';

// Money conversion helpers now live in pp_core; re-export so existing callers
// (manual_entry_screen, widget_test, etc.) need no import changes.
export 'package:pp_core/pp_core.dart' show dollarsToCents, centsToDollars;

final _twd = NumberFormat.currency(symbol: 'NT\$', decimalDigits: 0);
final _date = DateFormat('yyyy-MM-dd');

/// cents (e.g. 35000) -> "NT$350".
String formatTwd(int cents) => _twd.format(cents / 100);

String formatDate(DateTime d) => _date.format(d);

/// A foreign amount stored as minor units ×100 (the same fixed-point convention
/// as TWD cents) -> a localized currency string, e.g. (150000, 'JPY') -> "¥1,500",
/// (1250, 'USD') -> "US$12.50". `simpleCurrency` supplies the right symbol and
/// decimal-digit count per currency; an unknown code falls back to the code itself.
String formatForeign(int amountX100, String currencyCode) {
  try {
    final fmt = NumberFormat.simpleCurrency(name: currencyCode.toUpperCase());
    return fmt.format(amountX100 / 100);
  } catch (_) {
    return '${currencyCode.toUpperCase()} ${(amountX100 / 100).toStringAsFixed(2)}';
  }
}

/// A foreign→TWD rate formatted for display: 2 dp when ≥ 1, else 4 dp.
String formatRate(double rate) =>
    rate >= 1 ? rate.toStringAsFixed(2) : rate.toStringAsFixed(4);
