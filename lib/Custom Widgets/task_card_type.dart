/// Task card/UI type is driven by [task.service.belongs_to], not staff department
/// or [task.service.category].
class TaskCardType {
  TaskCardType._();

  static const String menuOrdering = 'menu ordering';
  static const String checkout = 'checkout';
  static const String lateCheckout = 'late checkout';

  /// Reads [task.service.belongs_to] regardless of map typing from JSON.
  static String? serviceBelongsTo(Map<String, dynamic> task) {
    final service = task['service'];
    if (service is! Map) return null;

    final dynamic raw = service['belongs_to'] ?? service['belongsTo'];
    if (raw == null) return null;

    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// True when [task.service.belongs_to] is Menu Ordering.
  static bool isMenuOrderingTask(Map<String, dynamic> task) {
    final belongsTo = serviceBelongsTo(task);
    if (belongsTo == null) return false;
    return _normalize(belongsTo) == menuOrdering;
  }

  /// Checkout / Late Checkout — handle on desktop web, not mobile assign.
  static bool isDesktopHandledTask(Map<String, dynamic> task) {
    final belongsTo = serviceBelongsTo(task);
    if (belongsTo == null) return false;
    final normalized = _normalize(belongsTo);
    return normalized == checkout || normalized == lateCheckout;
  }
}
