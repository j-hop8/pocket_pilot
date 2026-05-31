import 'package:intl/intl.dart';

final _twd = NumberFormat.currency(symbol: 'NT\$', decimalDigits: 0);
final _date = DateFormat('yyyy-MM-dd');
final _monthLabel = DateFormat('MMMM yyyy');

const _zhMonths = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十', '十一', '十二'];
const _enMonths = ['', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

/// cents (e.g. 35000) -> "NT$350".
String formatTwd(int cents) => _twd.format(cents / 100);

/// dollars typed by the user -> cents for storage.
int dollarsToCents(num dollars) => (dollars * 100).round();

/// cents -> dollars for editing in a form.
num centsToDollars(int cents) => cents / 100;

String formatDate(DateTime d) => _date.format(d);

String formatMonth(DateTime d) => _monthLabel.format(d);

/// "五月支出 · MAY" — Chinese month name + English abbreviation.
String formatMonthZh(DateTime d) =>
    '${_zhMonths[d.month]}月支出 · ${_enMonths[d.month]}';
