import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Config/primary_config.dart';

/// Network photo from a task service (`icon`, then `image`) or a menu line
/// (`itemImage`).
class TaskMedia {
  TaskMedia._();

  static String? networkUrl(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty || value == 'null') return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('//')) return 'https:$value';
    final domain = PrimaryConfigData.domainName;
    if (value.startsWith('/')) return '$domain$value';
    return '$domain/$value';
  }

  /// `service.icon`, then `service.image`.
  /// Example: `{ "service_name": "Towel", "icon": "https://…/icon.png", "image": "https://…/image.jpg" }`.
  static String? serviceIconUrl(Map<String, dynamic> task) {
    final service = task['service'];
    if (service is! Map) return null;
    return networkUrl(service['icon']) ?? networkUrl(service['image']);
  }

  static String? orderItemImageUrl(dynamic item) {
    if (item is! Map) return null;
    return networkUrl(item['itemImage'] ?? item['item_image']);
  }
}

class ServiceTaskIcon extends StatelessWidget {
  final Map<String, dynamic> task;
  final double size;

  const ServiceTaskIcon({
    super.key,
    required this.task,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final url = TaskMedia.serviceIconUrl(task);
    final primary = Theme.of(context).colorScheme.primary;
    if (url == null) {
      return Icon(Icons.room_service_outlined, color: primary, size: size * 0.7);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.room_service_outlined,
          color: primary,
          size: size * 0.7,
        ),
      ),
    );
  }
}

class OrderItemImage extends StatelessWidget {
  final dynamic item;
  final double size;

  const OrderItemImage({
    super.key,
    required this.item,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final url = TaskMedia.orderItemImageUrl(item);
    final primary = Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: primary.withValues(alpha: 0.08),
        child: url == null
            ? Icon(Icons.restaurant, color: primary, size: size * 0.5)
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.restaurant,
                  color: primary,
                  size: size * 0.5,
                ),
              ),
      ),
    );
  }
}
