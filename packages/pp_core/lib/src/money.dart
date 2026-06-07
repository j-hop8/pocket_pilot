// Money conversion helpers. All amounts in the app are stored as TWD cents
// (integer); CSVs and user input use TWD dollars (may be fractional).

/// TWD dollars → cents for storage.  e.g. 350.0 → 35000
int dollarsToCents(num dollars) => (dollars * 100).round();

/// Cents → TWD dollars for editing in a form.  e.g. 35000 → 350
num centsToDollars(int cents) => cents / 100;
