import 'package:flutter/material.dart';
import 'app_brand.dart';

import 'services/chatbot_faq_entry.dart';
import 'services/chatbot_faq_repository.dart';
import 'services/faq_library_search.dart';

class FaqLibraryPage extends StatefulWidget {
  const FaqLibraryPage({super.key});

  @override
  State<FaqLibraryPage> createState() => _FaqLibraryPageState();
}

class _FaqLibraryPageState extends State<FaqLibraryPage> {
  static const Color _accent = AppBrand.accent;

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedIds = {};

  List<ChatbotFaqEntry> _allEntries = [];
  bool _loading = true;

  String _query = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadFaqs();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFaqs() async {
    final cached = ChatbotFaqRepository.cachedEntries;
    if (cached.isNotEmpty) {
      setState(() {
        _allEntries = cached;
        _loading = false;
      });
      return;
    }

    final entries = await ChatbotFaqRepository.load();
    if (!mounted) return;
    setState(() {
      _allEntries = entries;
      _loading = false;
    });
  }

  List<ChatbotFaqEntry> get _visibleEntries {
    return FaqLibrarySearch.filter(
      entries: _allEntries,
      query: _query,
      categoryFilter: _selectedCategory,
    );
  }

  List<String> get _categories {
    return FaqLibrarySearch.orderedCategories(_allEntries);
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Help & FAQ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search FAQs...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _accent),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _categoryChip(label: 'All', category: null),
                      for (final category in _categories)
                        _categoryChip(
                          label: FaqCategoryLabels.labelFor(category),
                          category: category,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _visibleEntries.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: _visibleEntries.length,
                          itemBuilder: (context, index) {
                            final entry = _visibleEntries[index];
                            return _buildFaqTile(entry);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _categoryChip({required String label, required String? category}) {
    final selected = _selectedCategory == category ||
        (category == null && (_selectedCategory == null || _selectedCategory!.isEmpty));

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _selectedCategory = category);
        },
        backgroundColor: const Color(0xFF1A1A1A),
        selectedColor: _accent.withValues(alpha: 0.25),
        checkmarkColor: _accent,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected ? _accent : Colors.white10,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildFaqTile(ChatbotFaqEntry entry) {
    final expanded = _expandedIds.contains(entry.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _toggleExpanded(entry.id),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: expanded ? _accent.withValues(alpha: 0.45) : Colors.white10),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            FaqCategoryLabels.labelFor(entry.category),
                            style: TextStyle(
                              color: _accent.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.question,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: expanded ? _accent : Colors.white38,
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 12),
                  Text(
                    entry.answer,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.search_off, color: Colors.white38, size: 40),
            SizedBox(height: 14),
            Text(
              'No FAQs found.',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Try searching for appointments, payments, AI scan, haircuts, or account help.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
