import 'package:book_it/src/repositories/tenant_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Maps ISO 4217 currency codes to their display symbols.
const _currencySymbols = <String, String>{
  'ZAR': 'R',
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'AUD': r'A$',
  'CAD': r'C$',
  'JPY': '¥',
  'CNY': '¥',
  'INR': '₹',
  'BRL': r'R$',
  'KES': 'KSh',
  'NGN': '₦',
  'AED': 'AED',
  'CHF': 'CHF',
};

/// Returns the symbol for a given currency code, e.g. 'ZAR' → 'R'.
/// Falls back to the code itself if unknown.
String currencySymbol(String code) =>
    _currencySymbols[code.toUpperCase()] ?? code;

/// Formats [amount] with the currency symbol for [currencyCode].
/// Example: formatPrice(25.0, 'ZAR') → 'R 25.00'
String formatPrice(double amount, String currencyCode) {
  final symbol = currencySymbol(currencyCode);
  return '$symbol ${amount.toStringAsFixed(2)}';
}

/// Formats [amount] with no decimals.
/// Example: formatPriceShort(25.0, 'ZAR') → 'R 25'
String formatPriceShort(double amount, String currencyCode) {
  final symbol = currencySymbol(currencyCode);
  return '$symbol ${amount.toStringAsFixed(0)}';
}

/// Provider that exposes the active currency code from platform settings.
/// Defaults to 'ZAR' if settings haven't loaded yet.
final currencyCodeProvider = Provider<String>((ref) {
  final settingsAsync = ref.watch(platformSettingsProvider);
  return settingsAsync.when(
    data: (s) => s?.currency ?? 'ZAR',
    loading: () => 'ZAR',
    error: (_, __) => 'ZAR',
  );
});
