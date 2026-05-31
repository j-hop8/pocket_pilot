import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'strings.dart';

class LanguageNotifier extends Notifier<AppLang> {
  @override
  AppLang build() => AppLang.zh;

  void set(AppLang lang) => state = lang;
}

final languageProvider =
    NotifierProvider<LanguageNotifier, AppLang>(LanguageNotifier.new);

final stringsProvider = Provider<AppStrings>((ref) {
  return AppStrings(ref.watch(languageProvider));
});
