import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Screens/asap_task_page.dart';
import 'package:guestezee_staffs_app/Screens/cancelled_task_page.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';
import 'package:guestezee_staffs_app/Services/staff_service.dart';

/// Cancelled FAB, plus ASAP FAB above it when logged-in staff is at desk.
class DeskTaskFloatingActions extends StatelessWidget {
  const DeskTaskFloatingActions({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: StaffService.roleRevision,
      builder: (context, _, __) {
        final isDesk = StaffService.isAtDeskStaff(LocalStorageService.user);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isDesk) ...[
              FloatingActionButton(
                heroTag: 'asap_fab',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AsapTaskPage()),
                  );
                },
                backgroundColor: const Color(0xffE9CD3A),
                child: const Icon(Icons.bolt, color: Colors.black87),
              ),
              const SizedBox(height: 12),
            ],
            FloatingActionButton(
              heroTag: 'cancelled_fab',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CancelledTaskPage()),
                );
              },
              backgroundColor: Colors.red,
              child: const Icon(Icons.cancel_outlined, color: Colors.white),
            ),
          ],
        );
      },
    );
  }
}
