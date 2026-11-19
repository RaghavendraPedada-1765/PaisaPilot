import 'package:flutter/foundation.dart';

import 'format.dart';

/// What Activity shows. Shared through the shell so Home can open Activity
/// on one category and month.
@immutable
class ActivityFilter {
  const ActivityFilter({this.direction, this.category, this.categoryName, this.month, this.byAmount = false});

  final String? direction; // null = all, 'DR' = money out, 'CR' = money in
  final int? category; // null = every category, 0 = unsorted
  final String? categoryName; // shown on the chip
  final String? month; // 'YYYY-MM', null = all months
  final bool byAmount; // Largest first

  /// Home's donut slice: one category's spending in one month.
  factory ActivityFilter.slice({required int? categoryId, required String? categoryName, required String month}) =>
      ActivityFilter(
        direction: 'DR',
        category: categoryId ?? 0,
        categoryName: categoryName ?? 'Unsorted',
        month: month,
      );

  /// Narrows the rows (sorting does not).
  bool get narrows => direction != null || category != null || month != null;

  static const _keep = Object();

  ActivityFilter copyWith({
    Object? direction = _keep,
    Object? category = _keep,
    Object? categoryName = _keep,
    Object? month = _keep,
    bool? byAmount,
  }) =>
      ActivityFilter(
        direction: identical(direction, _keep) ? this.direction : direction as String?,
        category: identical(category, _keep) ? this.category : category as int?,
        categoryName: identical(categoryName, _keep) ? this.categoryName : categoryName as String?,
        month: identical(month, _keep) ? this.month : month as String?,
        byAmount: byAmount ?? this.byAmount,
      );

  ActivityFilter withoutCategory() => copyWith(category: null, categoryName: null);

  /// Plain-language description of the narrowing, e.g. `Money out ·
  /// Food and cafes · November 2026`.
  String describe() => [
        if (direction == 'DR') 'Money out',
        if (direction == 'CR') 'Money in',
        ?categoryName,
        if (month != null) monthLabel(month!),
      ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is ActivityFilter &&
      other.direction == direction &&
      other.category == category &&
      other.month == month &&
      other.byAmount == byAmount;

  @override
  int get hashCode => Object.hash(direction, category, month, byAmount);
}
