import 'package:intl/intl.dart';

import '../models/category.dart';

enum AppLang { zh, en }

const _zhMonths = [
  '', '一', '二', '三', '四', '五', '六',
  '七', '八', '九', '十', '十一', '十二'
];
final _monthFmt = DateFormat('MMMM yyyy');

class AppStrings {
  final AppLang lang;
  const AppStrings(this.lang);

  bool get _zh => lang == AppLang.zh;

  // ── Nav ────────────────────────────────────────────────────────────────────
  String get navHome     => _zh ? '首頁' : 'Home';
  String get navAdd      => _zh ? '新增' : 'Add';
  String get navHistory  => _zh ? '帳本' : 'History';
  String get navSettings => _zh ? '設定' : 'Settings';

  // ── Dashboard ──────────────────────────────────────────────────────────────
  String get noSpendingThisMonth => _zh ? '這個月還沒有消費' : 'No spending this month';
  String get scanToStart         => _zh ? '掃描發票開始記帳' : 'Scan a receipt to get started';
  String spendingCount(int n)    => _zh ? '$n 筆消費' : '$n transaction${n == 1 ? '' : 's'}';
  String get byCategory          => _zh ? '類別分析' : 'BY CATEGORY';
  String get categoryOther       => _zh ? '其他' : 'Other';
  String get incomeThisMonth     => _zh ? '收入' : 'INCOME';
  String get expenseThisMonth    => _zh ? '支出' : 'EXPENSE';
  String get netLabel            => _zh ? '結餘' : 'NET';

  String formatMonthHero(DateTime d) => _zh
      ? '${_zhMonths[d.month]}月支出'
      : _monthFmt.format(d).toUpperCase();

  /// Month navigator label, e.g. "2026年6月" / "June 2026".
  String formatMonthNav(DateTime d) =>
      _zh ? '${d.year}年${d.month}月' : _monthFmt.format(d);

  // ── Categories ───────────────────────────────────────────────────────────────
  /// Localized category name keyed by the language-independent category [key].
  /// Source of truth for display, so the mixed DB labels (e.g. "Shopping 購物")
  /// are never shown. A null/unknown key renders as "Uncategorized".
  String categoryName(String? key) => switch (key) {
    'groceries'     => _zh ? '超市'     : 'Groceries',
    'dining'        => _zh ? '餐飲'     : 'Dining',
    'transport'     => _zh ? '交通'     : 'Transport',
    'entertainment' => _zh ? '娛樂'     : 'Entertainment',
    'health'        => _zh ? '醫療健康' : 'Health',
    'utilities'     => _zh ? '水電費'   : 'Utilities',
    'shopping'      => _zh ? '購物'     : 'Shopping',
    'education'     => _zh ? '教育'     : 'Education',
    'travel'        => _zh ? '旅遊'     : 'Travel',
    'other'         => _zh ? '其他'     : 'Other',
    // Income categories.
    'salary'        => _zh ? '薪資'     : 'Salary',
    'bonus'         => _zh ? '獎金'     : 'Bonus',
    'investment'    => _zh ? '投資'     : 'Investment',
    'refund'        => _zh ? '退款'     : 'Refund',
    'gift'          => _zh ? '禮金'     : 'Gift',
    'other_income'  => _zh ? '其他收入' : 'Other income',
    _               => _zh ? '未分類'   : 'Uncategorized',
  };

  /// Display name for a resolved category: built-ins use the localized name
  /// above; user-created / edited categories carry their own (single-language)
  /// [Category.label]. A null category renders as "Uncategorized".
  String catName(Category? c) {
    if (c == null) return uncategorized;
    return c.isBuiltin ? categoryName(c.key) : c.label;
  }

  // ── Manage categories ────────────────────────────────────────────────────────
  String get manageCategories  => _zh ? '管理類別'   : 'CATEGORIES';
  String get manageCategoriesHint =>
      _zh ? '新增、編輯或刪除你的收支類別' : 'Add, edit or delete your categories';
  String get categoriesTitle   => _zh ? '類別'       : 'Categories';
  String get addCategory       => _zh ? '新增類別'   : 'Add category';
  String get editCategory      => _zh ? '編輯類別'   : 'Edit category';
  String get categoryNameLabel => _zh ? '名稱'       : 'Name';
  String get enterCategoryName => _zh ? '請輸入名稱。' : 'Enter a name.';
  String get chooseIcon        => _zh ? '圖示'       : 'Icon';
  String get chooseColor       => _zh ? '顏色'       : 'Color';
  String get noCategoriesYet   => _zh ? '還沒有類別'  : 'No categories yet';
  String get deleteCategoryTitle => _zh ? '刪除這個類別？' : 'Delete this category?';
  String get deleteCategoryBody  => _zh
      ? '使用此類別的帳目會變成「未分類」。'
      : 'Records using it will become "Uncategorized".';
  String categorySaveFailed(Object e) =>
      _zh ? '儲存失敗：$e' : 'Save failed: $e';
  String categoryDeleteFailed(Object e) =>
      _zh ? '刪除失敗：$e' : 'Delete failed: $e';

  // ── Budget ─────────────────────────────────────────────────────────────────
  String get budgetSectionLabel => _zh ? '預算'        : 'BUDGET';
  String get budgetsTitle       => _zh ? '預算'        : 'Budgets';
  String get overallBudgetLabel => _zh ? '每月總預算'  : 'Overall monthly budget';
  String get setBudget          => _zh ? '設定預算'    : 'Set budget';
  String get editBudget         => _zh ? '編輯預算'    : 'Edit budget';
  String get removeBudget       => _zh ? '移除預算'    : 'Remove budget';
  String get budgetAmountLabel  => _zh ? '每月預算（NT\$）' : 'Monthly budget (NT\$)';
  String get notSetLabel        => _zh ? '未設定'      : 'Not set';
  String get setABudgetCta      => _zh ? '設定每月預算' : 'Set a monthly budget';
  String get noBudgetsYet       => _zh ? '還沒有預算'  : 'No budgets yet';
  String get enterValidBudget   => _zh ? '請輸入大於 0 的金額。' : 'Enter an amount greater than 0.';
  String get removeBudgetTitle  => _zh ? '移除這個預算？' : 'Remove this budget?';
  String get removeBudgetBody   => _zh
      ? '這個預算將被刪除，消費仍會保留。'
      : 'This budget will be deleted. Your spending is unaffected.';
  String budgetPerMonth(int cents) =>
      _zh ? 'NT\$${cents ~/ 100} / 月' : 'NT\$${cents ~/ 100} / mo';
  String spentOfText(int spent, int limit) =>
      'NT\$${spent ~/ 100} / NT\$${limit ~/ 100}';
  String remainingText(int cents) =>
      _zh ? '剩 NT\$${cents ~/ 100}' : 'NT\$${cents ~/ 100} left';
  String overByText(int cents) =>
      _zh ? '超支 NT\$${cents ~/ 100}' : 'Over by NT\$${cents ~/ 100}';
  String budgetSaveFailed(Object e) =>
      _zh ? '儲存失敗：$e' : 'Save failed: $e';
  String budgetDeleteFailed(Object e) =>
      _zh ? '刪除失敗：$e' : 'Delete failed: $e';

  // ── History ────────────────────────────────────────────────────────────────
  String get noHistory       => _zh ? '還沒有帳目'     : 'No records yet';
  String get deleteTitle     => _zh ? '刪除這筆帳目？'  : 'Delete this record?';
  String get deleteBody      => _zh ? '刪除後無法復原。' : 'This action cannot be undone.';
  String get cancel          => _zh ? '取消'           : 'Cancel';
  String get delete          => _zh ? '刪除'           : 'Delete';
  String get unknownMerchant => _zh ? '未知商家'       : 'Unknown';
  String get uncategorized   => _zh ? '未分類'         : 'Uncategorized';
  String get lookupMerchant  => _zh ? '查詢店名'       : 'Look up name';
  String merchantFound(String name) => _zh ? '已找到：$name' : 'Found: $name';
  String get merchantNotFound =>
      _zh ? '查無此統編的店名' : "Couldn't find a name for this tax ID";

  // ── History filters ──────────────────────────────────────────────────────────
  String get filterKindTitle     => _zh ? '類型'       : 'Type';
  String get filterAllKinds      => _zh ? '全部'       : 'All';
  String get filterCategoryLabel => _zh ? '類別'       : 'Category';
  String get filterTimeLabel     => _zh ? '時間'       : 'Time';
  String get matchByInvoice      => _zh ? '依發票'     : 'By invoice';
  String get matchByItem         => _zh ? '依品項'     : 'By item';
  String get timeAll             => _zh ? '全部時間'   : 'All time';
  String get timeThisMonth       => _zh ? '本月'       : 'This month';
  String get timeLast30          => _zh ? '近 30 天'   : 'Last 30 days';
  String get timeThisYear        => _zh ? '今年'       : 'This year';
  String get timeCustom          => _zh ? '自訂範圍'   : 'Custom range';
  String get noMatches           => _zh ? '沒有符合的帳目' : 'No matching records';
  String get clearFilters        => _zh ? '清除'       : 'Clear';
  String categoryCount(int n)    => _zh ? '$n 個類別'  : '$n categories';
  String resultsCount(int n)     => _zh ? '$n 筆'      : '$n result${n == 1 ? '' : 's'}';

  // ── Capture ────────────────────────────────────────────────────────────────
  // Source tabs: 0 = manual entry, 1 = e-invoice QR, 2 = paper receipt.
  String get tabManual   => _zh ? '手動'       : 'Manual';
  String get tabEInvoice => _zh ? '電子發票'   : 'e-Invoice';
  String get tabReceipt  => _zh ? '收據'       : 'Receipt';

  // Only used by the camera tabs (e-invoice / receipt); the manual tab has no frame.
  String hintFor(int srcIndex) => switch (srcIndex) {
    2 => _zh ? '把收據對準框框'          : 'Align the paper receipt with the frame',
    _ => _zh ? '把發票上的 QR 對準框框'  : 'Align the QR code on the receipt with the frame',
  };

  String get manualPanelTitle => _zh ? '手動輸入' : 'Enter it yourself';
  String get manualPanelHint  =>
      _zh ? '直接填寫發票資料並送出' : 'Type in the invoice details and submit';

  // ── Scan (e-invoice QR) ──────────────────────────────────────────────────────
  String get scanStart        => _zh ? '開始掃描' : 'Scan';
  String get scanChooseTitle  => _zh ? '掃描電子發票' : 'Scan an e-invoice';
  String get scanOpenCamera   => _zh ? '開啟相機' : 'Open camera';
  String get scanPickFromFolder => _zh ? '從檔案選擇' : 'Pick from folder';
  String get scanning         => _zh ? '掃描中…' : 'Scanning…';
  String get scanReading      => _zh ? '讀取中…' : 'Reading…';
  String get scanCameraDenied => _zh ? '需要相機權限才能掃描。' : 'Camera access is needed to scan.';
  String get scanCameraUnsupported => _zh
      ? '此瀏覽器或裝置無法開啟相機（網頁需在 https 或 localhost 才能使用相機）。'
      : "This browser or device can't open the camera (the web needs https or localhost for camera access).";
  String get scanCameraError  => _zh ? '無法開啟相機。' : "Couldn't open the camera.";
  String get scanCameraOpening => _zh ? '正在開啟相機…' : 'Opening camera…';
  String get scanCapture      => _zh ? '拍照辨識' : 'Capture';
  String get scanRetry        => _zh ? '重試' : 'Try again';
  String scanSaveFailed(Object e) => _zh ? '儲存失敗：$e' : 'Save failed: $e';
  String get scanAdded        => _zh ? '已加入' : 'Added';

  // ── Scan (receipt OCR) ───────────────────────────────────────────────────────
  String get scanReceiptChooseTitle => _zh ? '掃描收據' : 'Scan a receipt';
  String get scanReceiptHint => _zh
      ? '拍照或從相簿選擇，AI 會自動讀取收據內容記帳'
      : 'Snap a photo or pick from your library — AI reads it and adds it for you';
  String get scanTakePhoto => _zh ? '拍照' : 'Take photo';
  String scanLimitReached(int limit) => _zh
      ? '今天的掃描已達上限（每天 $limit 次），請明天再試。'
      : 'Daily scan limit reached ($limit/day). Try again tomorrow.';

  // ── Background scan queue (progress overlay) ─────────────────────────────────
  String queueTitle(int n) => _zh
      ? '處理 $n 張發票…'
      : 'Adding $n receipt${n == 1 ? '' : 's'}…';
  String get queueAllDone   => _zh ? '全部完成' : 'All done';
  String get queueDuplicate => _zh ? '已存在' : 'Already added';
  String get queueFailed    => _zh ? '讀取失敗' : "Couldn't read";
  String get queueMinimize  => _zh ? '縮小' : 'Minimize';
  String get queueDismiss   => _zh ? '清除' : 'Dismiss';

  // ── Manual entry ───────────────────────────────────────────────────────────
  String get addInvoice        => _zh ? '新增帳目'         : 'Add invoice';
  String get editInvoice       => _zh ? '編輯帳目'         : 'Edit invoice';
  String get addIncome         => _zh ? '新增收入'         : 'Add income';
  String get editIncome        => _zh ? '編輯收入'         : 'Edit income';
  String get expenseLabel      => _zh ? '支出'             : 'Expense';
  String get incomeLabel       => _zh ? '收入'             : 'Income';
  String get incomeSourceLabel => _zh ? '來源'             : 'Source';
  String get amountLabel       => _zh ? '金額（NT\$）'     : 'Amount (NT\$)';
  String get enterAmount       => _zh ? '請輸入金額。'     : 'Enter an amount.';
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
  String get edit                => _zh ? '編輯'       : 'Edit';
  String get changeCategory      => _zh ? '變更類別'   : 'Change category';
  String get officialLockedHint  => _zh
      ? '此發票來自官方同步，僅可變更類別。'
      : 'Synced from the official e-invoice — only the category can be changed.';
  String datePrefix(String d)    => _zh ? '日期：$d'   : 'Date: $d';
  String qtyText(num qty, int? unit, String formattedUnit) => unit == null
      ? (_zh ? '數量 $qty' : 'Qty $qty')
      : (_zh ? '數量 $qty × $formattedUnit' : 'Qty $qty × $formattedUnit');

  // ── Settings ───────────────────────────────────────────────────────────────
  String get settingsTitle  => _zh ? '設定'   : 'Settings';
  String get languageLabel  => _zh ? '語言'   : 'LANGUAGE';
  String get langZh         => '繁體中文';
  String get langEn         => 'English';

  // ── Auth ───────────────────────────────────────────────────────────────────
  String get signInTitle   => _zh ? '登入以同步你的發票' : 'Sign in to sync your invoices';
  String get signInSubtitle => _zh
      ? '用 Google 帳號登入，你的發票與消費只有你看得到。'
      : 'Sign in with Google. Your invoices and spending stay private to you.';
  String get signInWithGoogle => _zh ? '使用 Google 登入' : 'Continue with Google';
  String get signInFailed     => _zh ? '登入失敗，請再試一次。' : 'Sign-in failed. Please try again.';
  String get tryDemo          => _zh ? '先試用 Demo' : 'Try the demo';
  String get accountLabel     => _zh ? '帳號' : 'ACCOUNT';
  String get signOut          => _zh ? '登出' : 'Sign out';
  String get demoAccountName  => _zh ? '訪客（Demo）' : 'Demo (guest)';
  String get demoAccountHint  => _zh ? '暫時的 Demo 帳號' : 'Temporary demo account';
  String get demoCarrierUnavailable => _zh
      ? '載具同步在 Demo 帳號中無法使用。'
      : 'Carrier sync isn\'t available in demo mode.';

  // ── Carrier sync ─────────────────────────────────────────────────────────────
  String get carrierSyncLabel  => _zh ? '發票同步' : 'CARRIER SYNC';
  String get autoSyncLabel     => _zh ? '自動同步' : 'Auto-sync';
  String get autoSyncHint      => _zh
      ? '定期登入財政部下載新發票'
      : 'Periodically logs in and pulls new invoices';
  String get syncIntervalLabel => _zh ? '同步頻率' : 'SYNC INTERVAL';
  String get syncNow           => _zh ? '立即同步' : 'Sync now';
  String get syncing           => _zh ? '同步中…' : 'Syncing…';
  String get syncNever         => _zh ? '尚未同步' : 'Not synced yet';

  /// Label for an interval in minutes (60 / 360 / 720 / 1440).
  String syncIntervalOption(int minutes) => switch (minutes) {
    60   => _zh ? '每小時'   : 'Hourly',
    360  => _zh ? '每 6 小時' : 'Every 6h',
    720  => _zh ? '每 12 小時' : 'Every 12h',
    1440 => _zh ? '每天'     : 'Daily',
    _    => _zh ? '$minutes 分鐘' : '$minutes min',
  };

  String lastSyncedText(String date, int count) => _zh
      ? '上次同步 $date · $count 筆'
      : 'Last sync $date · $count invoices';

  String syncOkSnack(int inserted) => _zh
      ? (inserted == 0 ? '同步完成：沒有新發票' : '同步完成：新增 $inserted 筆')
      : (inserted == 0 ? 'Synced: no new invoices' : 'Synced: $inserted new');

  String syncFailedError(Object e) =>
      _zh ? '同步失敗：$e' : 'Sync failed: $e';

  String get syncStatusErrorPrefix =>
      _zh ? '上次同步失敗' : 'Last sync failed';

  // ── Carrier sync screen ──────────────────────────────────────────────────────
  String get carrierSyncTitle    => _zh ? '載具同步' : 'Carrier sync';
  String get carrierCredentials  => _zh ? '載具帳密' : 'Carrier credentials';
  String get carrierCredsHint    => _zh
      ? '財政部電子發票平台的登入資訊，儲存後會用於自動同步，定期為你抓取最新發票。'
      : 'E-invoice portal login. Saved credentials power auto-sync, which periodically pulls your latest invoices.';
  String get credentialsSaved    => _zh ? '帳密已儲存' : 'Credentials saved';
  String get phoneLabel          => _zh ? '手機號碼' : 'Phone';
  String get passwordLabel       => _zh ? '密碼' : 'Password';
  String get leaveBlankKeep      => _zh ? '留空則沿用目前密碼' : 'Leave blank to keep current';
  String get credsStorageWarning => _zh
      ? '此 demo 將帳密儲存於 Supabase，請勿在共用環境輸入真實密碼。'
      : 'Stored in Supabase for this demo. Don\'t use a real password in a shared environment.';
  String get updateCredentials   => _zh ? '更新帳密' : 'Update credentials';
  String get saveCredentials     => _zh ? '儲存帳密' : 'Save credentials';
  String get credsSavedSnack     => _zh ? '帳密已儲存' : 'Credentials saved';
  String get removeCredentials   => _zh ? '移除帳密' : 'Remove credentials';
  String get removeCredsTitle    => _zh ? '移除已儲存的帳密？' : 'Remove saved credentials?';
  String get removeCredsBody     => _zh
      ? '將從你的帳號刪除手機號碼與密碼，並關閉自動同步。之後需要重新輸入才能再次同步。'
      : 'Your phone number and password will be deleted from your account and auto-sync will be turned off. You\'ll need to enter them again to sync.';
  String get removeCredsConfirm  => _zh ? '移除' : 'Remove';
  String get credsRemovedSnack   => _zh ? '帳密已移除' : 'Credentials removed';
  String removeFailedError(Object e) =>
      _zh ? '移除失敗：$e' : 'Remove failed: $e';
  String get notSyncedYetLong    => _zh
      ? '尚未同步 — 自動同步即將執行，或於下方立即同步 / 匯入 CSV。'
      : 'Not synced yet — auto-sync will run soon, or sync now / import a CSV below.';

  String get syncNowDescConnected    => _zh
      ? '自動登入並抓取你最新的發票。'
      : 'Log in and pull your latest invoices automatically.';
  String get syncNowDescDisconnected => _zh
      ? '請先在上方儲存載具帳密，再執行同步。'
      : 'Save your carrier credentials above first, then run a sync.';

  String get importInvoices     => _zh ? '匯入發票' : 'Import invoices';
  String get importInvoicesHint => _zh
      ? '從電子發票平台下載「消費明細」CSV，再到這裡匯入；重複的發票會自動略過。'
      : 'Download your invoice CSV from the e-invoice portal (消費明細), then import it here. Duplicates are skipped automatically.';
  String get whenToUseTitle => _zh ? '使用時機' : 'When to use this';
  String get whenToUseBody  => _zh
      ? '自動同步會定期為你抓取發票，平常不需要手動操作。CSV 匯入適合補抓較早的發票，或在同步失敗、最新發票還沒出現時手動補匯（重複自動略過）。'
      : 'Auto-sync now pulls your invoices periodically, so you usually don\'t need to do anything. Use CSV import to backfill older invoices, or as a fallback when a sync fails or your latest invoices haven\'t shown up yet — re-import and any new ones are added (duplicates skipped).';
  String get importing      => _zh ? '匯入中…' : 'Importing…';
  String get chooseCsvFile  => _zh ? '選擇 CSV 檔案' : 'Choose CSV file';
  String get couldNotReadFile => _zh ? '無法讀取檔案內容。' : 'Could not read file contents.';
  String get noInvoicesInFile => _zh ? '檔案中沒有發票。' : 'No invoices found in that file.';
  String get lastImport       => _zh ? '上次匯入' : 'Last import';

  String importedSnack(int inserted, int skipped) => _zh
      ? '已匯入 $inserted 筆，略過 $skipped 筆。'
      : 'Imported $inserted new, skipped $skipped.';
  String importFailedError(Object e) => _zh ? '匯入失敗：$e' : 'Import failed: $e';
  String newInvoicesStat(int n) => _zh ? '$n 筆新發票' : '$n new invoices';
  String lineItemsStat(int n)   => _zh ? '$n 筆品項' : '$n line items';
  String skippedStat(int n)     => _zh ? '$n 筆已存在（略過）' : '$n already present (skipped)';
  String lastSyncLine(String date, int count) => _zh
      ? '上次同步：$date（$count 筆）'
      : 'Last sync: $date ($count invoices)';
}
