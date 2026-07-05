import 'package:flutter_test/flutter_test.dart';
import 'package:pocketpilot/features/dashboard/dashboard_screen.dart';

void main() {
  group('budgetProgress', () {
    test('under budget reports the exact fraction and not over', () {
      final p = budgetProgress(2500, 10000);
      expect(p.fraction, closeTo(0.25, 1e-9));
      expect(p.over, isFalse);
    });

    test('exactly at the limit is full but not over', () {
      final p = budgetProgress(10000, 10000);
      expect(p.fraction, 1.0);
      expect(p.over, isFalse);
    });

    test('over budget clamps the bar to 1.0 and flags over', () {
      final p = budgetProgress(15000, 10000);
      expect(p.fraction, 1.0);
      expect(p.over, isTrue);
    });

    test('zero spend is empty', () {
      final p = budgetProgress(0, 10000);
      expect(p.fraction, 0.0);
      expect(p.over, isFalse);
    });

    test('non-positive limit is treated as no budget', () {
      final p = budgetProgress(5000, 0);
      expect(p.fraction, 0.0);
      expect(p.over, isFalse);
    });
  });
}
