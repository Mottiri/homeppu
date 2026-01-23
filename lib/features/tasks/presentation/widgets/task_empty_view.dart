import 'package:flutter/material.dart';

class TaskEmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onTap;
  final Color? textColor;

  const TaskEmptyView({
    super.key,
    required this.icon,
    required this.message,
    this.onTap,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: TextStyle(
                        color: textColor ?? Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
