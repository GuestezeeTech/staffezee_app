import 'package:flutter/material.dart';

/// Shared header hotel name (profile / home app bar).
Widget hotelNameHeader({
  required BuildContext context,
  required String name,
  Widget? loadingPlaceholder,
}) {
  return SizedBox(
    height: MediaQuery.of(context).size.height * 0.075,
    width: MediaQuery.of(context).size.width * 0.35,
    child: Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.35,
        ),
        child: loadingPlaceholder ??
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
      ),
    ),
  );
}
