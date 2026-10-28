import 'package:flutter/services.dart';

// Quantities may have decimals (e.g. 15.5 Kg); ERPNext applies UOM rules.
const quantityKeyboardType = TextInputType.numberWithOptions(decimal: true);

// Returns the typed quantity, or null if it is not a number above zero.
// Accepts a comma as decimal separator, as some keypads only show ','.
double? parseQuantity(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

// Shows 15.0 as "15" and 15.5 as "15.5".
String formatQuantity(double value) =>
    value == value.truncateToDouble() ? value.toInt().toString() : '$value';
