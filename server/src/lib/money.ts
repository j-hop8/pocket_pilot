// Port of packages/pp_core/lib/src/money.dart — TWD dollars → integer cents.
export function dollarsToCents(dollars: number): number {
  return Math.round(dollars * 100);
}
