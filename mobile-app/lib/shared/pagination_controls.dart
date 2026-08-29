import 'package:flutter/material.dart';

class PaginationControls extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final int maxVisiblePages;

  const PaginationControls({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.maxVisiblePages = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) {
      return const SizedBox.shrink();
    }

    final safeCurrentPage = currentPage.clamp(1, totalPages);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 400;
          final visible = compact
              ? (maxVisiblePages > 3 ? 3 : maxVisiblePages)
              : maxVisiblePages;
          final pages = _visiblePages(safeCurrentPage, totalPages, visible);

          Widget prevButton() {
            final enabled = safeCurrentPage > 1;
            if (compact) {
              return IconButton(
                onPressed: enabled ? () => onPageChanged(safeCurrentPage - 1) : null,
                icon: const Icon(Icons.chevron_left),
                color: Colors.white,
                disabledColor: Colors.white24,
                tooltip: 'Previous',
              );
            }
            return OutlinedButton(
              onPressed: enabled ? () => onPageChanged(safeCurrentPage - 1) : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
              child: const Text('Previous'),
            );
          }

          Widget nextButton() {
            final enabled = safeCurrentPage < totalPages;
            if (compact) {
              return IconButton(
                onPressed: enabled ? () => onPageChanged(safeCurrentPage + 1) : null,
                icon: const Icon(Icons.chevron_right),
                color: Colors.white,
                disabledColor: Colors.white24,
                tooltip: 'Next',
              );
            }
            return OutlinedButton(
              onPressed: enabled ? () => onPageChanged(safeCurrentPage + 1) : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
              child: const Text('Next'),
            );
          }

          return Row(
            children: [
              prevButton(),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: pages.map((page) {
                      final isActive = page == safeCurrentPage;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: SizedBox(
                          width: 34,
                          child: ElevatedButton(
                            onPressed: isActive ? null : () => onPageChanged(page),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor:
                                  isActive ? Colors.white : const Color(0xFF1A1A1A),
                              foregroundColor: isActive ? Colors.black : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              side: BorderSide(
                                  color: isActive ? Colors.white : Colors.white24),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text('$page'),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              nextButton(),
            ],
          );
        },
      ),
    );
  }

  List<int> _visiblePages(int current, int total, int maxVisible) {
    if (total <= maxVisible) {
      return List<int>.generate(total, (index) => index + 1);
    }

    final half = maxVisible ~/ 2;
    var start = current - half;
    var end = current + half;

    if (maxVisible.isEven) {
      end -= 1;
    }

    if (start < 1) {
      end += (1 - start);
      start = 1;
    }

    if (end > total) {
      start -= (end - total);
      end = total;
    }

    if (start < 1) {
      start = 1;
    }

    return List<int>.generate(end - start + 1, (index) => start + index);
  }
}
