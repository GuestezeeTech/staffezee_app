import 'package:flutter/material.dart';

class TaskSpecialRequest {
  static String? text(Map<String, dynamic>? task) {
    if (task == null) return null;
    final taskDescription = task['task_description']?.toString().trim();
    if (taskDescription != null && taskDescription.isNotEmpty) {
      return taskDescription;
    }

    final helpRemarks = task['help_remarks']?.toString().trim();
    if (helpRemarks != null && helpRemarks.isNotEmpty) {
      return helpRemarks;
    }

    return null;
  }

  static Widget section(
    Map<String, dynamic> task, {
    bool withTopSpacing = true,
  }) {
    final description = text(task);
    if (description == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (withTopSpacing) const SizedBox(height: 16),
        Text(
          'Special Request',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border.all(color: const Color(0xffE7E7E7)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  static Widget inlineSubtitle(Map<String, dynamic> task) {
    final description = text(task);
    if (description == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        description,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[600],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
