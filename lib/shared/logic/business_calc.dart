class VatResult {
  const VatResult(this.supply, this.vat, this.total);

  final int supply;
  final int vat;
  final int total;
}

/// Korean VAT 10%. Amounts are whole won.
VatResult vatFromSupply(int supply) {
  final vat = (supply * 0.1).round();
  return VatResult(supply, vat, supply + vat);
}

VatResult vatFromTotal(int total) {
  final supply = (total / 1.1).round();
  return VatResult(supply, total - supply, total);
}

double discountedPrice(double price, double ratePercent) => price * (1 - ratePercent / 100);

/// Margin rate on the selling price, in percent. Null when the price is zero.
double? marginRate(double cost, double price) => price == 0 ? null : (price - cost) / price * 100;

/// Markup on cost, in percent. Null when the cost is zero.
double? markupRate(double cost, double price) => cost == 0 ? null : (price - cost) / cost * 100;

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Calendar days from [a] to [b] (b - a).
int daysBetween(DateTime a, DateTime b) => _day(b).difference(_day(a)).inDays;

/// Weekdays (Mon–Fri) from [a] to [b] inclusive, in either order. Public holidays are not excluded.
int businessDays(DateTime a, DateTime b) {
  var from = _day(a);
  var to = _day(b);
  if (to.isBefore(from)) (from, to) = (to, from);
  final total = to.difference(from).inDays + 1;
  final weeks = total ~/ 7;
  var count = weeks * 5;
  for (var i = 0; i < total % 7; i++) {
    final wd = from.add(Duration(days: weeks * 7 + i)).weekday;
    if (wd <= DateTime.friday) count++;
  }
  return count;
}
