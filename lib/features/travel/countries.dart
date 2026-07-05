import '../../core/strings.dart';

/// A travel destination the user can pick when creating a trip. Picking a
/// country derives the [currencyCode] used for receipt conversion. Curated to
/// common destinations (a static list keeps this dependency-free); the user can
/// always pick another country with the same currency.
class TravelCountry {
  final String code; // ISO 3166-1 alpha-2
  final String currencyCode; // ISO 4217
  final String nameEn;
  final String nameZh;
  final String flag; // emoji

  const TravelCountry({
    required this.code,
    required this.currencyCode,
    required this.nameEn,
    required this.nameZh,
    required this.flag,
  });

  String name(AppLang lang) => lang == AppLang.zh ? nameZh : nameEn;
}

/// Common destinations for a Taiwan-based traveller, alphabetical-ish by region.
const List<TravelCountry> travelCountries = [
  TravelCountry(code: 'JP', currencyCode: 'JPY', nameEn: 'Japan', nameZh: '日本', flag: '🇯🇵'),
  TravelCountry(code: 'KR', currencyCode: 'KRW', nameEn: 'South Korea', nameZh: '韓國', flag: '🇰🇷'),
  TravelCountry(code: 'HK', currencyCode: 'HKD', nameEn: 'Hong Kong', nameZh: '香港', flag: '🇭🇰'),
  TravelCountry(code: 'MO', currencyCode: 'MOP', nameEn: 'Macau', nameZh: '澳門', flag: '🇲🇴'),
  TravelCountry(code: 'CN', currencyCode: 'CNY', nameEn: 'China', nameZh: '中國', flag: '🇨🇳'),
  TravelCountry(code: 'SG', currencyCode: 'SGD', nameEn: 'Singapore', nameZh: '新加坡', flag: '🇸🇬'),
  TravelCountry(code: 'MY', currencyCode: 'MYR', nameEn: 'Malaysia', nameZh: '馬來西亞', flag: '🇲🇾'),
  TravelCountry(code: 'TH', currencyCode: 'THB', nameEn: 'Thailand', nameZh: '泰國', flag: '🇹🇭'),
  TravelCountry(code: 'VN', currencyCode: 'VND', nameEn: 'Vietnam', nameZh: '越南', flag: '🇻🇳'),
  TravelCountry(code: 'PH', currencyCode: 'PHP', nameEn: 'Philippines', nameZh: '菲律賓', flag: '🇵🇭'),
  TravelCountry(code: 'ID', currencyCode: 'IDR', nameEn: 'Indonesia', nameZh: '印尼', flag: '🇮🇩'),
  TravelCountry(code: 'IN', currencyCode: 'INR', nameEn: 'India', nameZh: '印度', flag: '🇮🇳'),
  TravelCountry(code: 'US', currencyCode: 'USD', nameEn: 'United States', nameZh: '美國', flag: '🇺🇸'),
  TravelCountry(code: 'CA', currencyCode: 'CAD', nameEn: 'Canada', nameZh: '加拿大', flag: '🇨🇦'),
  TravelCountry(code: 'GB', currencyCode: 'GBP', nameEn: 'United Kingdom', nameZh: '英國', flag: '🇬🇧'),
  TravelCountry(code: 'FR', currencyCode: 'EUR', nameEn: 'France', nameZh: '法國', flag: '🇫🇷'),
  TravelCountry(code: 'DE', currencyCode: 'EUR', nameEn: 'Germany', nameZh: '德國', flag: '🇩🇪'),
  TravelCountry(code: 'IT', currencyCode: 'EUR', nameEn: 'Italy', nameZh: '義大利', flag: '🇮🇹'),
  TravelCountry(code: 'ES', currencyCode: 'EUR', nameEn: 'Spain', nameZh: '西班牙', flag: '🇪🇸'),
  TravelCountry(code: 'NL', currencyCode: 'EUR', nameEn: 'Netherlands', nameZh: '荷蘭', flag: '🇳🇱'),
  TravelCountry(code: 'CH', currencyCode: 'CHF', nameEn: 'Switzerland', nameZh: '瑞士', flag: '🇨🇭'),
  TravelCountry(code: 'AU', currencyCode: 'AUD', nameEn: 'Australia', nameZh: '澳洲', flag: '🇦🇺'),
  TravelCountry(code: 'NZ', currencyCode: 'NZD', nameEn: 'New Zealand', nameZh: '紐西蘭', flag: '🇳🇿'),
  TravelCountry(code: 'AE', currencyCode: 'AED', nameEn: 'United Arab Emirates', nameZh: '阿聯', flag: '🇦🇪'),
  TravelCountry(code: 'TR', currencyCode: 'TRY', nameEn: 'Türkiye', nameZh: '土耳其', flag: '🇹🇷'),
  TravelCountry(code: 'KH', currencyCode: 'KHR', nameEn: 'Cambodia', nameZh: '柬埔寨', flag: '🇰🇭'),
  TravelCountry(code: 'TW', currencyCode: 'TWD', nameEn: 'Taiwan', nameZh: '台灣', flag: '🇹🇼'),
];

/// The picked country for a [code], or null if it isn't in the curated list.
TravelCountry? countryByCode(String? code) {
  if (code == null) return null;
  for (final c in travelCountries) {
    if (c.code == code) return c;
  }
  return null;
}
