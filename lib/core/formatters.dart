import 'package:intl/intl.dart';

// Money conversion helpers now live in pp_core; re-export so existing callers
// (manual_entry_screen, widget_test, etc.) need no import changes.
export 'package:pp_core/pp_core.dart' show dollarsToCents, centsToDollars;

final _twd = NumberFormat.currency(symbol: 'NT\$', decimalDigits: 0);
final _date = DateFormat('yyyy-MM-dd');

/// cents (e.g. 35000) -> "NT$350".
String formatTwd(int cents) => _twd.format(cents / 100);

String formatDate(DateTime d) => _date.format(d);
