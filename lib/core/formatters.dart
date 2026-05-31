import 'package:intl/intl.dart';

/// Money is stored as INTEGER TWD cents everywhere. Only this layer converts
/// to/from a human display value.
final _twd = NumberFormat.currency(symbol: 'NT\$', decimalDigits: 0);
final _date = DateFormat('yyyy-MM-dd');
final _monthLabel = DateFormat('MMMM yyyy');

/// cents (e.g. 35000) -> "NT$350".
String formatTwd(int cents) => _twd.format(cents / 100);

/// dollars typed by the user -> cents for storage.
int dollarsToCents(num dollars) => (dollars * 100).round();

/// cents -> dollars for editing in a form.
num centsToDollars(int cents) => cents / 100;

String formatDate(DateTime d) => _date.format(d);

String formatMonth(DateTime d) => _monthLabel.format(d);
