import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/stamp_sheet_service.dart';

class StampSheetArchivesScreen extends ConsumerStatefulWidget {
  const StampSheetArchivesScreen({super.key});

  @override
  ConsumerState<StampSheetArchivesScreen> createState() =>
      _StampSheetArchivesScreenState();
}

class _StampSheetArchivesScreenState
    extends ConsumerState<StampSheetArchivesScreen> {
  static const int _columnsPerPage = 3;
  static const int _rowsPerPage = 3;
  static const int _itemsPerPage = _columnsPerPage * _rowsPerPage;
  static const double _cardAspectRatio = 0.72; // width / height
  static const double _captionGap = 4.0;
  static const double _captionHeight = 14.0;

  final _sheetService = StampSheetService();
  final _pageController = PageController();
  Future<List<StampSheetDefinition>>? _catalogFuture;
  Future<Map<String, StampSheetLayout>>? _layoutsFuture;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _sheetService.fetchCatalog();
    _layoutsFuture = _loadLayouts();
  }

  Future<Map<String, StampSheetLayout>> _loadLayouts() async {
    final sheets = await _catalogFuture!;
    final map = <String, StampSheetLayout>{};
    for (final sheet in sheets) {
      map[sheet.id] = await _sheetService.loadLayout(sheet);
    }
    return map;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatCompletedAt(DateTime? value) {
    if (value == null) return '-';
    final v = value.toLocal();
    final y = v.year.toString().padLeft(4, '0');
    final m = v.month.toString().padLeft(2, '0');
    final d = v.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppMessages.stamp.archiveTitle)),
        body: Center(child: Text(AppMessages.error.loginRequired)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppMessages.stamp.archiveTitle)),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: FutureBuilder<List<StampSheetDefinition>>(
          future: _catalogFuture,
          builder: (context, catalogSnapshot) {
            if (!catalogSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            final sheets = catalogSnapshot.data!;
            final sheetById = {for (final sheet in sheets) sheet.id: sheet};

            return FutureBuilder<Map<String, StampSheetLayout>>(
              future: _layoutsFuture,
              builder: (context, layoutSnapshot) {
                if (!layoutSnapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                final layouts = layoutSnapshot.data!;

                return StreamBuilder<List<StampSheetArchive>>(
                  stream: _sheetService.watchArchives(user.uid),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }
                    final archives = snapshot.data!;
                    if (archives.isEmpty) {
                      return Center(
                        child: Text(AppMessages.stamp.archiveEmpty),
                      );
                    }

                    final totalPages =
                        (archives.length + _itemsPerPage - 1) ~/ _itemsPerPage;
                    if (_currentPage >= totalPages) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final target = totalPages - 1;
                        setState(() => _currentPage = target);
                        _pageController.jumpToPage(target);
                      });
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              const horizontalSpacing = 32.0;
                              const verticalSpacing = 6.0;
                              const topPadding = 6.0;
                              const bottomPadding = 0.0;
                              const sideMargin = 10.0;
                              const maxCardWidthLimit = 280.0;
                              final availableHeight =
                                  constraints.maxHeight - topPadding - bottomPadding;
                              final maxCellWidthByLayout =
                                  ((constraints.maxWidth - (sideMargin * 2)) -
                                      ((_columnsPerPage - 1) *
                                          horizontalSpacing)) /
                                  _columnsPerPage;
                              final maxCellWidth =
                                  maxCellWidthByLayout < maxCardWidthLimit
                                  ? maxCellWidthByLayout
                                  : maxCardWidthLimit;
                              final maxCellHeight =
                                  (availableHeight -
                                      ((_rowsPerPage - 1) * verticalSpacing)) /
                                  _rowsPerPage;
                              final maxCardHeight =
                                  (maxCellHeight - _captionGap - _captionHeight)
                                              .isNegative
                                      ? maxCellHeight
                                      : (maxCellHeight - _captionGap - _captionHeight);
                              final maxCardWidthByHeight =
                                  maxCardHeight * _cardAspectRatio;
                              final cardWidth = maxCellWidth < maxCardWidthByHeight
                                  ? maxCellWidth
                                  : maxCardWidthByHeight;
                              final cardHeight = cardWidth / _cardAspectRatio;
                              final cellWidth = cardWidth;
                              final cellHeight =
                                  cardHeight + _captionGap + _captionHeight;
                              final cellAspectRatio = cellWidth / cellHeight;
                              final gridWidth =
                                  (_columnsPerPage * cellWidth) +
                                  ((_columnsPerPage - 1) * horizontalSpacing);
                              final horizontalPadding =
                                  ((constraints.maxWidth - gridWidth) / 2) <
                                      sideMargin
                                  ? sideMargin
                                  : ((constraints.maxWidth - gridWidth) / 2);
                              final verticalPadding = topPadding;

                              return PageView.builder(
                                controller: _pageController,
                                onPageChanged: (index) {
                                  if (!mounted) return;
                                  setState(() => _currentPage = index);
                                },
                                itemCount: totalPages,
                                itemBuilder: (context, pageIndex) {
                                  final start = pageIndex * _itemsPerPage;
                                  final end =
                                      (start + _itemsPerPage) > archives.length
                                      ? archives.length
                                      : (start + _itemsPerPage);
                                  final pageItems = archives.sublist(
                                    start,
                                    end,
                                  );

                                  return GridView.builder(
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(
                                      horizontalPadding,
                                      verticalPadding,
                                      horizontalPadding,
                                      bottomPadding,
                                    ),
                                    itemCount: pageItems.length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: _columnsPerPage,
                                          crossAxisSpacing: horizontalSpacing,
                                          mainAxisSpacing: verticalSpacing,
                                          childAspectRatio: cellAspectRatio,
                                        ),
                                    itemBuilder: (context, index) {
                                      final archive = pageItems[index];
                                      final sheet = sheetById[archive.sheetId];
                                      final layout = layouts[archive.sheetId];
                                      return _ArchiveCard(
                                        archive: archive,
                                        sheet: sheet,
                                        layout: layout,
                                        formatCompletedAt: _formatCompletedAt,
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        if (totalPages > 1)
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(totalPages, (index) {
                                  final selected = index == _currentPage;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    width: selected ? 10 : 8,
                                    height: selected ? 10 : 8,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.textTertiary,
                                      shape: BoxShape.circle,
                                      boxShadow: selected
                                          ? [
                                              BoxShadow(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 6,
                                                offset: const Offset(0, 1),
                                              ),
                                            ]
                                          : null,
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({
    required this.archive,
    required this.sheet,
    required this.layout,
    required this.formatCompletedAt,
  });

  final StampSheetArchive archive;
  final StampSheetDefinition? sheet;
  final StampSheetLayout? layout;
  final String Function(DateTime?) formatCompletedAt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: sheet != null && layout != null
                ? _ArchiveSheetPreview(
                    sheetAssetPath: sheet!.assetPath,
                    layout: layout!,
                    bySlot: archive.bySlot,
                  )
                : Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    color: AppColors.surfaceVariant,
                    child: Text(
                      AppMessages.stamp.archivePreviewUnavailable,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            AppMessages.stamp.archiveCompletedAt(
              formatCompletedAt(archive.completedAt),
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _ArchiveSheetPreview extends StatelessWidget {
  const _ArchiveSheetPreview({
    required this.sheetAssetPath,
    required this.layout,
    required this.bySlot,
  });

  final String sheetAssetPath;
  final StampSheetLayout layout;
  final Map<String, String> bySlot;

  ReactionType? _reactionById(String id) {
    for (final type in ReactionType.values) {
      if (type.value == id) return type;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: layout.aspectRatio > 0 ? layout.aspectRatio : (2 / 3),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(sheetAssetPath, fit: BoxFit.fill),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              return Stack(
                children: [
                  for (final slot in layout.slots)
                    if (bySlot[slot.slotId] != null)
                      Positioned(
                        left: slot.x * width,
                        top: slot.y * height,
                        width: slot.w * width,
                        height: slot.h * height,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Image.asset(
                            _reactionById(bySlot[slot.slotId]!)?.assetPath ??
                                '',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox(),
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
