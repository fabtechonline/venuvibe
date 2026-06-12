/// A tenant-defined extra a customer can add to a booking (racquet hire,
/// table hire, cutlery…), priced per unit with a per-booking quantity cap.
class ResourceAddon {
  const ResourceAddon({
    required this.resourceId,
    required this.name,
    required this.price,
    this.id = '',
    this.maxQty = 10,
    this.isActive = true,
  });

  factory ResourceAddon.fromJson(Map<String, dynamic> json) {
    return ResourceAddon(
      id: json['id'] as String? ?? '',
      resourceId: json['resource_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      maxQty: json['max_qty'] as int? ?? 10,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
  final String id;
  final String resourceId;
  final String name;
  final double price;
  final int maxQty;
  final bool isActive;

  Map<String, dynamic> toJson() => {
        'resource_id': resourceId,
        'name': name,
        'price': price,
        'max_qty': maxQty,
        'is_active': isActive,
      };
}

/// A line item on a booking. Name and unit price are SNAPSHOTS taken at
/// booking time, so later catalog edits never rewrite past orders.
class BookingAddon {
  const BookingAddon({
    required this.bookingId,
    required this.name,
    required this.unitPrice,
    required this.qty,
    this.id = '',
    this.addonId,
  });

  factory BookingAddon.fromJson(Map<String, dynamic> json) {
    return BookingAddon(
      id: json['id'] as String? ?? '',
      bookingId: json['booking_id'] as String,
      addonId: json['addon_id'] as String?,
      name: json['name'] as String,
      unitPrice: (json['unit_price'] as num).toDouble(),
      qty: json['qty'] as int,
    );
  }
  final String id;
  final String bookingId;
  final String? addonId;
  final String name;
  final double unitPrice;
  final int qty;

  double get lineTotal => unitPrice * qty;
}
