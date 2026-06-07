// Pure-TS port of packages/pp_core/lib/src/categorizer.dart.
// Keep the rule list + ordering identical to the Dart original.

// Ordered (key, keywords). Merchant name is matched first against every group
// in order, then the item names. Groceries/convenience stores precede dining so
// a convenience-store purchase is classified by store type, not a food keyword.
const RULES: ReadonlyArray<readonly [string, readonly string[]]> = [
  ["transport", [
    "加油", "中油", "台塑石化", "停車", "捷運", "高鐵", "台鐵", "客運", "計程車",
    "uber", "公車", "悠遊", "一卡通", "etc", "遠通", "通行費", "租車",
  ]],
  ["health", [
    "藥局", "藥妝", "藥品", "診所", "醫院", "醫療", "牙醫", "屈臣氏", "康是美",
    "大樹", "丁丁", "杏一", "健保",
  ]],
  ["utilities", [
    "中華電信", "台灣大哥大", "遠傳", "亞太電信", "電信", "台電", "電費",
    "自來水", "水費", "瓦斯", "天然氣",
  ]],
  ["entertainment", [
    "電影", "影城", "威秀", "國賓", "秀泰", "ktv", "錢櫃", "好樂迪", "netflix",
    "spotify", "disney", "steam", "遊戲", "遊樂", "playstation",
  ]],
  ["travel", [
    "航空", "機票", "飯店", "酒店", "旅館", "旅店", "民宿", "訂房", "agoda",
    "booking", "旅行社", "長榮航", "華航", "星宇",
  ]],
  ["education", ["補習", "文具", "書局", "書店", "學費", "課程", "教育"]],
  ["shopping", [
    "百貨", "服飾", "服裝", "寶雅", "小三美日", "momo", "pchome", "蝦皮",
    "家具", "ikea", "五金", "特力", "光南", "燦坤", "3c", "網購",
  ]],
  ["groceries", [
    "超市", "超商", "便利商店", "全聯", "全家", "統一超商", "7-", "711",
    "萊爾富", "ok mart", "頂好", "美廉社", "量販", "家樂福", "大潤發",
    "好市多", "costco", "生鮮",
  ]],
  ["dining", [
    "餐", "飲", "食", "早餐", "咖啡", "茶", "飯", "麵", "麵包", "吐司", "蛋糕",
    "甜", "烘焙", "便當", "火鍋", "燒烤", "串", "炸", "雞", "豬", "牛", "羊",
    "披薩", "pizza", "漢堡", "壽司", "拉麵", "滷", "鍋", "飲料", "手搖",
    "奶茶", "星巴克", "麥當勞", "肯德基", "摩斯", "食堂", "小吃", "點心", "烤",
  ]],
];

/// Best-effort category key from a merchant name and/or its item names.
export function categorizeKey(
  merchant: string | null | undefined,
  itemNames: ReadonlyArray<string> = [],
): string {
  const merchantHay = (merchant ?? "").toLowerCase();
  const itemsHay = itemNames.join(" ").toLowerCase();
  return firstMatch(merchantHay) ?? firstMatch(itemsHay) ?? "other";
}

function firstMatch(hay: string): string | null {
  if (hay.trim() === "") return null;
  for (const [key, keywords] of RULES) {
    for (const kw of keywords) {
      if (hay.includes(kw)) return key;
    }
  }
  return null;
}
