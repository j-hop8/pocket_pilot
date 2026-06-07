import 'package:csv/csv.dart';

/// One parsed invoice (header + line items) from a Ministry of Finance carrier
/// "消費明細" (detail) CSV export.
class ParsedInvoice {
  final String invoiceNumber;
  final DateTime date;
  final String? merchantName; // 賣方名稱
  final String? carrierName; // 載具自訂名稱
  final String? sellerAddress; // 賣方地址
  final List<ParsedItem> items;

  ParsedInvoice({
    required this.invoiceNumber,
    required this.date,
    this.merchantName,
    this.carrierName,
    this.sellerAddress,
    required this.items,
  });

  /// Invoice total in **TWD dollars** = sum of line amounts.
  ///
  /// The CSV's 發票金額 column is unreliable — for multi-line invoices it
  /// mirrors the per-line amount rather than the invoice total — so we always
  /// sum the line items (discount lines are negative and net correctly).
  int get totalDollars => items.fold(0, (sum, i) => sum + i.amount);
}

/// A single line item, amounts in **TWD dollars** (the CSV is not in cents).
class ParsedItem {
  final String name; // 消費明細_品名
  final num quantity; // 消費明細_數量
  final int unitPrice; // 消費明細_單價
  final int amount; // 消費明細_金額

  const ParsedItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
  });
}

// 2 letters + 8 digits (digits may be masked with '*' for voided/donated ones).
final _invoiceNoRe = RegExp(r'^[A-Z]{2}[0-9*]{8}$');
final _dateRe = RegExp(r'^\d{8}$');

/// Parses a MOF carrier detail CSV into invoices grouped by invoice number.
///
/// Robust to the file's quirks: a UTF-8 BOM, CRLF line endings, the header row,
/// and the 2 trailing footnote lines (all skipped because only rows with a
/// valid invoice number + YYYYMMDD date are accepted). Columns are located by
/// header name, falling back to fixed positions if the header is missing.
List<ParsedInvoice> parseEinvoiceCsv(String csv) {
  var text = csv;
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1); // strip UTF-8 BOM
  }
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
      .convert(text);
  if (rows.isEmpty) return const [];

  final col = _columnIndex(rows);

  // Preserve first-seen order while grouping by invoice number.
  final order = <String>[];
  final groups = <String, _InvoiceAccumulator>{};

  for (final row in rows) {
    if (row.length <= col.item) continue;
    final no = _cell(row, col.number);
    final dateStr = _cell(row, col.date);
    if (!_invoiceNoRe.hasMatch(no) || !_dateRe.hasMatch(dateStr)) {
      continue; // header, footnotes, or any misaligned row
    }

    final acc = groups.putIfAbsent(no, () {
      order.add(no);
      return _InvoiceAccumulator(
        invoiceNumber: no,
        date: _parseDate(dateStr),
        merchantName: _nullIfEmpty(_cell(row, col.merchant)),
        carrierName: _nullIfEmpty(_cell(row, col.carrier)),
        sellerAddress: _nullIfEmpty(_cell(row, col.address)),
      );
    });

    final name = _cell(row, col.item);
    if (name.isEmpty) continue;
    acc.items.add(ParsedItem(
      name: name,
      quantity: num.tryParse(_cell(row, col.qty)) ?? 1,
      unitPrice: _toInt(_cell(row, col.unitPrice)),
      amount: _toInt(_cell(row, col.amount)),
    ));
  }

  return [
    for (final no in order)
      if (groups[no]!.items.isNotEmpty) groups[no]!.build(),
  ];
}

class _Columns {
  final int carrier, date, number, merchant, address, qty, unitPrice, amount,
      item;
  const _Columns(this.carrier, this.date, this.number, this.merchant,
      this.address, this.qty, this.unitPrice, this.amount, this.item);
}

_Columns _columnIndex(List<List<dynamic>> rows) {
  final byName = <String, int>{};
  for (final row in rows) {
    if (row.any((c) => c.toString().trim() == '發票號碼') &&
        row.any((c) => c.toString().trim() == '消費明細_品名')) {
      for (var i = 0; i < row.length; i++) {
        byName[row[i].toString().trim()] = i;
      }
      break;
    }
  }
  int idx(String name, int fallback) => byName[name] ?? fallback;
  return _Columns(
    idx('載具自訂名稱', 0),
    idx('發票日期', 1),
    idx('發票號碼', 2),
    idx('賣方名稱', 7),
    idx('賣方地址', 8),
    idx('消費明細_數量', 10),
    idx('消費明細_單價', 11),
    idx('消費明細_金額', 12),
    idx('消費明細_品名', 13),
  );
}

class _InvoiceAccumulator {
  final String invoiceNumber;
  final DateTime date;
  final String? merchantName;
  final String? carrierName;
  final String? sellerAddress;
  final List<ParsedItem> items = [];

  _InvoiceAccumulator({
    required this.invoiceNumber,
    required this.date,
    this.merchantName,
    this.carrierName,
    this.sellerAddress,
  });

  ParsedInvoice build() => ParsedInvoice(
        invoiceNumber: invoiceNumber,
        date: date,
        merchantName: merchantName,
        carrierName: carrierName,
        sellerAddress: sellerAddress,
        items: items,
      );
}

String _cell(List<dynamic> row, int i) =>
    i < row.length ? row[i].toString().trim() : '';

String? _nullIfEmpty(String s) => s.isEmpty ? null : s;

DateTime _parseDate(String yyyymmdd) => DateTime(
      int.parse(yyyymmdd.substring(0, 4)),
      int.parse(yyyymmdd.substring(4, 6)),
      int.parse(yyyymmdd.substring(6, 8)),
    );

int _toInt(String s) =>
    int.tryParse(s) ?? (double.tryParse(s)?.round() ?? 0);
