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
    final pages = _visiblePages(safeCurrentPage, totalPages, maxVisiblePages);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(
            onPressed: safeCurrentPage > 1
                ? () => onPageChanged(safeCurrentPage - 1)
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
            ),
            child: const Text('Previous'),
          ),
          const SizedBox(width: 8),
          ...pages.map((page) {
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
          }),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: safeCurrentPage < totalPages
                ? () => onPageChanged(safeCurrentPage + 1)
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
            ),
            child: const Text('Next'),
          ),
        ],
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
