import 'package:intl/intl.dart';

// Money conversion helpers now live in pp_core; re-export so existing callers
// (manual_entry_screen, widget_test, etc.) need no import changes.
export 'package:pp_core/pp_core.dart' show dollarsToCents, centsToDollars;

final _twd = NumberFormat.currency(symbol: 'NT\$', decimalDigits: 0);
final _date = DateFormat('yyyy-MM-dd');
final _monthLabel = DateFormat('MMMM yyyy');

const _zhMonths = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十', '十一', '十二'];
const _enMonths = ['', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

/// cents (e.g. 35000) -> "NT$350".
String formatTwd(int cents) => _twd.format(cents / 100);

String formatDate(DateTime d) => _date.format(d);

String formatMonth(DateTime d) => _monthLabel.format(d);

/// "五月支出 · MAY" — Chinese month name + English abbreviation.
String formatMonthZh(DateTime d) =>
    '${_zhMonths[d.month]}月支出 · ${_enMonths[d.month]}';
