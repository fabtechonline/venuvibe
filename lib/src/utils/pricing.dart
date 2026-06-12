/// Client-side mirrors of the server-side pricing in
/// create_booking_with_addons / approve_custom_booking (0013). Display only —
/// the database RPCs are the source of truth for what gets charged.
library;

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Price for a custom time-range booking: hourly rate pro-rated to minutes.
double customBasePrice(double hourlyRate, int minutes) =>
    _round2(hourlyRate * minutes / 60);

/// Platform commission: rate% of (base − discount + add-ons).
double commissionOn({
  required double base,
  required double addons,
  required double ratePercent,
  double discount = 0,
}) =>
    _round2((base - discount + addons) * ratePercent / 100);

/// Grand total the customer pays.
double orderTotal({
  required double base,
  required double addons,
  required double ratePercent,
  double discount = 0,
}) =>
    _round2(
      base -
          discount +
          addons +
          commissionOn(
            base: base,
            addons: addons,
            discount: discount,
            ratePercent: ratePercent,
          ),
    );
