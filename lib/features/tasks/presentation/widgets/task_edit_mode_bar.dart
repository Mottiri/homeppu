import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TaskEditModeBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final VoidCallback onClose;
  final VoidCallback? onDelete;
  final PreferredSizeWidget? bottom;
  final SystemUiOverlayStyle? systemOverlayStyle;

  const TaskEditModeBar({
    super.key,
    required this.selectedCount,
    required this.onClose,
    this.onDelete,
    this.bottom,
    this.systemOverlayStyle,
  });

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        '$selectedCount件 選択中',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.orange.shade50,
      foregroundColor: Colors.black87,
      systemOverlayStyle: systemOverlayStyle,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: onClose,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: onDelete,
        ),
      ],
      bottom: bottom,
    );
  }
}
