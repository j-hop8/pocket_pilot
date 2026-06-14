import 'einvoice_csv_parser.dart' show ParsedItem;

/// One e-invoice decoded from a 電子發票證明聯 QR code (the **left** QR — the
/// **right** QR only carries overflow item detail).
///
/// Money fields are **TWD dollars** (whole NT$), matching [ParsedItem] and the
/// CSV path; the app converts to cents with `dollarsToCents` at ingest.
///
/// The left QR's fixed 77-char header (invoice number / date / amounts / tax
/// ids) is a stable government format and always parsed. Item triples in the
/// tail (and the right QR) are **best-effort**: [hasFullItems] is only true when
/// the parsed triples match the count the QR declares. Anything ambiguous —
/// including Big5-encoded names (a follow-up) — leaves [items] empty so the
/// caller falls back to a single header-total line.
class ParsedQrInvoice {
  final String invoiceNumber; // e.g. BM18825967
  final DateTime date;
  final String randomCode; // 隨機碼, 4 digits
  final int salesAmountDollars; // 銷售額 (pre-tax)
  final int totalDollars; // 總計額 (tax-incl.) — authoritative, from the header
  final String? buyerTaxId; // null when 00000000 (B2C)
  final String? sellerTaxId; // 賣方統一編號 — the merchant lookup key
  final String? sellerCustom; // 營業人自行使用區 (POS data), null when blank
  final int declaredItemCount; // item count the QR claims (0 if unreadable)
  final List<ParsedItem> items; // parsed triples (may be empty/partial)
  final String rawLeft;
  final String? rawRight;

  const ParsedQrInvoice({
    required this.invoiceNumber,
    required this.date,
    required this.randomCode,
    required this.salesAmountDollars,
    required this.totalDollars,
    this.buyerTaxId,
    this.sellerTaxId,
    this.sellerCustom,
    this.declaredItemCount = 0,
    this.items = const [],
    required this.rawLeft,
    this.rawRight,
  });

  /// True when we recovered the complete itemization, so the caller can store
  /// the real line items instead of a single synthetic header-total line.
  bool get hasFullItems =>
      declaredItemCount > 0 && items.length == declaredItemCount;
}

// 2 uppercase letters + 8 digits (QR numbers are never masked, unlike the CSV).
final _qrInvoiceNoRe = RegExp(r'^[A-Z]{2}\d{8}$');
final _hexRe = RegExp(r'^[0-9A-Fa-f]{8}$');

/// Parses the **left** QR ([left]) of a 電子發票證明聯, optionally merging the
/// **right** QR ([right]) for the rest of the item detail.
///
/// Returns `null` if [left] isn't a valid e-invoice left QR (wrong length, bad
/// header). Robust to a flipped scan order: if [left] looks like a right QR
/// (`**…`) and [right] holds the header, they are swapped.
ParsedQrInvoice? parseEinvoiceQr({required String left, String? right}) {
  var head = left;
  var tail = right;
  // Tolerate the two QRs arriving in the wrong order.
  if (head.startsWith('**') && tail != null && !tail.startsWith('**')) {
    final t = head;
    head = tail;
    tail = t;
  }
  if (head.length < 77) return null;

  final invoiceNumber = head.substring(0, 10);
  if (!_qrInvoiceNoRe.hasMatch(invoiceNumber)) return null;

  final dateStr = head.substring(10, 17); // ROC YYYMMDD
  final date = _parseRocDate(dateStr);
  if (date == null) return null;

  final salesHex = head.substring(21, 29);
  final totalHex = head.substring(29, 37);
  if (!_hexRe.hasMatch(salesHex) || !_hexRe.hasMatch(totalHex)) return null;

  final randomCode = head.substring(17, 21);
  final salesAmount = int.parse(salesHex, radix: 16);
  final totalAmount = int.parse(totalHex, radix: 16);
  final buyerTaxId = _taxIdOrNull(head.substring(37, 45));
  final sellerTaxId = _taxIdOrNull(head.substring(45, 53));

  // ── Tail (after the 77-char header): seller-custom + item detail ──────────
  // Layout: <sellerCustom>:<totalCount>:<perInvoiceCount>:<encoding>:
  //         <name>:<qty>:<price>:…   (encoding 0=UTF-8, 1=Big5)
  // There is NO reserved field between the seller-custom area and the counts,
  // and *both* count fields hold the invoice-wide item total (real POS systems
  // do not record a per-QR split here) — so we just collect triples greedily
  // from the left tail, then continue into the right QR, up to [total].
  // Best-effort — any deviation yields no items (header-only fallback).
  String? sellerCustom;
  var declaredCount = 0;
  final items = <ParsedItem>[];

  final tailTokens = _tail(head).split(':');
  if (tailTokens.isNotEmpty) {
    sellerCustom = tailTokens[0].isEmpty || tailTokens[0] == '**********'
        ? null
        : tailTokens[0];

    // Need at least: totalCount, perInvoiceCount, encoding. Item triples are
    // optional here — an invoice can carry all of them on the right QR.
    if (tailTokens.length >= 4) {
      final total = int.tryParse(tailTokens[1]);
      final encoding = tailTokens[3];
      if (total != null) {
        declaredCount = total;
        // Big5 names can't be recovered from the decoded string → skip items.
        if (encoding == '0') {
          items.addAll(_triples(tailTokens.sublist(4), total));
          // The right QR is the literal marker '**' *prefixed* to the first
          // overflow item name (NOT a standalone '**' token), then more
          // :name:qty:price triples — so strip the 2-char prefix, don't split.
          if (items.length < total && tail != null && tail.startsWith('**')) {
            final rightTokens = tail.substring(2).split(':');
            items.addAll(_triples(rightTokens, total - items.length));
          }
        }
      }
    }
  }

  return ParsedQrInvoice(
    invoiceNumber: invoiceNumber,
    date: date,
    randomCode: randomCode,
    salesAmountDollars: salesAmount,
    totalDollars: totalAmount,
    buyerTaxId: buyerTaxId,
    sellerTaxId: sellerTaxId,
    sellerCustom: sellerCustom,
    declaredItemCount: declaredCount,
    items: items,
    rawLeft: left,
    rawRight: right,
  );
}

/// Everything after the 77-char header, without the leading ':'.
String _tail(String head) {
  if (head.length <= 77) return '';
  final t = head.substring(77);
  return t.startsWith(':') ? t.substring(1) : t;
}

/// Reads up to [count] `(name, qty, unitPrice)` triples from [tokens]. Stops on
/// any malformed triple so a misparsed stream can't fabricate items.
List<ParsedItem> _triples(List<String> tokens, int count) {
  final out = <ParsedItem>[];
  for (var i = 0; i + 2 < tokens.length && out.length < count; i += 3) {
    final name = tokens[i].trim();
    final qty = num.tryParse(tokens[i + 1]);
    final price = num.tryParse(tokens[i + 2]);
    if (name.isEmpty || qty == null || price == null) break;
    out.add(ParsedItem(
      name: name,
      quantity: qty,
      unitPrice: price.round(),
      amount: (qty * price).round(),
    ));
  }
  return out;
}

DateTime? _parseRocDate(String yyymmdd) {
  if (yyymmdd.length != 7 || int.tryParse(yyymmdd) == null) return null;
  final year = int.parse(yyymmdd.substring(0, 3)) + 1911;
  final month = int.parse(yyymmdd.substring(3, 5));
  final day = int.parse(yyymmdd.substring(5, 7));
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

String? _taxIdOrNull(String id) =>
    (id == '00000000' || id.trim().isEmpty) ? null : id;
