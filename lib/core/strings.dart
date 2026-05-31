import 'package:intl/intl.dart';

enum AppLang { zh, en }

const _zhMonths = [
  '', '一', '二', '三', '四', '五', '六',
  '七', '八', '九', '十', '十一', '十二'
];
const _enMonths = [
  '', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
];
final _monthFmt = DateFormat('MMMM yyyy');

class AppStrings {
  final AppLang lang;
  const AppStrings(this.lang);

  bool get _zh => lang == AppLang.zh;

  // ── Nav ────────────────────────────────────────────────────────────────────
  String get navHome     => _zh ? '首頁' : 'Home';
  String get navCapture  => _zh ? '掃描' : 'Scan';
  String get navHistory  => _zh ? '帳本' : 'History';
  String get navSettings => _zh ? '設定' : 'Settings';

  // ── Dashboard ──────────────────────────────────────────────────────────────
  String get noSpendingThisMonth => _zh ? '這個月還沒有消費' : 'No spending this month';
  String get scanToStart         => _zh ? '掃描發票開始記帳' : 'Scan a receipt to get started';
  String spendingCount(int n)    => _zh ? '$n 筆消費' : '$n transaction${n == 1 ? '' : 's'}';
  String get byCategory          => _zh ? '類別分析' : 'BY CATEGORY';
  String get categoryOther       => _zh ? '其他' : 'Other';

  String formatMonthHero(DateTime d) => _zh
      ? '${_zhMonths[d.month]}月支出 · ${_enMonths[d.month]}'
      : _monthFmt.format(d).toUpperCase();

  // ── History ────────────────────────────────────────────────────────────────
  String get noHistory       => _zh ? '還沒有帳目'     : 'No records yet';
  String get deleteTitle     => _zh ? '刪除這筆帳目？'  : 'Delete this record?';
  String get deleteBody      => _zh ? '刪除後無法復原。' : 'This action cannot be undone.';
  String get cancel          => _zh ? '取消'           : 'Cancel';
  String get delete          => _zh ? '刪除'           : 'Delete';
  String get unknownMerchant => _zh ? '未知商家'       : 'Unknown';
  String get uncategorized   => _zh ? '未分類'         : 'Uncategorized';

  // ── Capture ────────────────────────────────────────────────────────────────
  String get tabCarrier => _zh ? '載具'   : 'Carrier';
  String get tabQR      => _zh ? '掃 QR'  : 'Scan QR';
  String get tabPaper   => _zh ? '紙本'   : 'Paper';

  String hintFor(int srcIndex) => switch (srcIndex) {
    0 => _zh ? '請先在財政部綁定手機載具'    : 'Link your phone carrier in the MoF app first',
    2 => _zh ? '把紙本發票對準框框'          : 'Align the paper receipt with the frame',
    _ => _zh ? '把發票上的 QR 對準框框'      : 'Align the QR code on the receipt with the frame',
  };

  String get pointCamera => _zh ? '對準發票'   : 'POINT CAMERA AT RECEIPT';
  String get manualEntry => _zh ? '手動輸入'   : 'Manual entry';

  // ── Manual entry ───────────────────────────────────────────────────────────
  String get addInvoice        => _zh ? '新增帳目'         : 'Add invoice';
  String get dateLabel         => _zh ? '日期'             : 'Date';
  String get merchantLabel     => _zh ? '商家'             : 'Merchant';
  String get invoiceCategory   => _zh ? '帳目類別'         : 'Invoice category';
  String get itemsLabel        => _zh ? '品項'             : 'Items';
  String get addItem           => _zh ? '新增品項'         : 'Add item';
  String get itemName          => _zh ? '品名'             : 'Item name';
  String get qtyLabel          => _zh ? '數量'             : 'Qty';
  String get unitPrice         => _zh ? '單價（NT\$）'     : 'Unit price (NT\$)';
  String get itemCategory      => _zh ? '品項類別'         : 'Item category';
  String get remove            => _zh ? '移除'             : 'Remove';
  String get totalLabel        => _zh ? '總計'             : 'Total';
  String get save              => _zh ? '儲存'             : 'Save';
  String get addAtLeastOneItem => _zh ? '請至少輸入一筆品項名稱。' : 'Add at least one item with a name.';
  String get saveFailed        => _zh ? '儲存失敗'         : 'Save failed';
  String get failedToLoad      => _zh ? '載入失敗'         : 'Failed to load';
  String get failedToLoadCats  => _zh ? '載入類別失敗'     : 'Failed to load categories';

  String failedToLoadError(Object e) => _zh ? '載入失敗：$e' : 'Failed to load: $e';
  String saveFailedError(Object e)   => _zh ? '儲存失敗：$e' : 'Save failed: $e';

  // ── Invoice detail ─────────────────────────────────────────────────────────
  String get invoiceTitle        => _zh ? '帳目明細'   : 'Invoice';
  String get unknownMerchantLong => _zh ? '未知商家'   : 'Unknown merchant';
  String get invoiceNoPrefix     => _zh ? '發票號碼：' : 'Invoice no.: ';
  String get noLineItems         => _zh ? '沒有品項資料。' : 'No line items.';
  String datePrefix(String d)    => _zh ? '日期：$d'   : 'Date: $d';
  String qtyText(num qty, int? unit, String formattedUnit) => unit == null
      ? (_zh ? '數量 $qty' : 'Qty $qty')
      : (_zh ? '數量 $qty × $formattedUnit' : 'Qty $qty × $formattedUnit');

  // ── Settings ───────────────────────────────────────────────────────────────
  String get settingsTitle  => _zh ? '設定'   : 'Settings';
  String get languageLabel  => _zh ? '語言'   : 'LANGUAGE';
  String get langZh         => '繁體中文';
  String get langEn         => 'English';
}
