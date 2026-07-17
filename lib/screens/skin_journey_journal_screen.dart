// lib/screens/skin_journey_journal_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';
import '../models/product_tracker.dart';
import '../models/procedure.dart' as models;
import '../models/journal_entry.dart';
import '../utils/app_prefs.dart';

class SkinJourneyJournalScreen extends StatefulWidget {
  final Map<String, List<JournalEntry>> skincareJournals;
  final List<TrackedProduct> trackedProducts;
  final List<models.Procedure> activeProcedures;

  const SkinJourneyJournalScreen({
    super.key,
    required this.skincareJournals,
    required this.trackedProducts,
    this.activeProcedures = const [],
  });

  @override
  State<SkinJourneyJournalScreen> createState() =>
      _SkinJourneyJournalScreenState();
}

class _SkinJourneyJournalScreenState extends State<SkinJourneyJournalScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _showProcedureEntries = true;
  bool _showSkincareEntries = true;

  List<Map<String, dynamic>> get _procedureEntries {
    final list = <Map<String, dynamic>>[];
    for (
      int procedureIndex = 0;
      procedureIndex < widget.activeProcedures.length;
      procedureIndex++
    ) {
      final proc = widget.activeProcedures[procedureIndex];
      for (
        int entryIndex = 0;
        entryIndex < proc.journalEntries.length;
        entryIndex++
      ) {
        final entry = proc.journalEntries[entryIndex];
        list.add({
          'type': 'procedure',
          'title': proc.type,
          'subtitle': entry.date.toLocal().toString().split(' ')[0],
          'content': entry.content,
          'mood': entry.moodRating,
          'image': entry.attachedImagePath,
          'procedure': proc,
          'entry': entry,
          'procedureIndex': procedureIndex,
          'entryIndex': entryIndex,
        });
      }
    }
    list.sort(
      (a, b) => (b['entry'] as JournalEntry).date.compareTo(
        (a['entry'] as JournalEntry).date,
      ),
    );
    return list;
  }

  List<Map<String, dynamic>> get _skincareEntries {
    final list = <Map<String, dynamic>>[];
    widget.skincareJournals.forEach((productName, entries) {
      final product = widget.trackedProducts.firstWhere(
        (p) => p.name == productName,
        orElse: () => TrackedProduct(
          id: '',
          name: productName,
          brand: '',
          keyIngredients: '',
          startDate: DateTime.now(),
          notes: '',
        ),
      );
      for (int entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        final entry = entries[entryIndex];
        list.add({
          'type': 'skincare',
          'title': product.brand.isNotEmpty
              ? '${product.brand} - ${product.name}'
              : productName,
          'subtitle': entry.date.toLocal().toString().split(' ')[0],
          'content': entry.content,
          'mood': entry.moodRating,
          'image': entry.attachedImagePath,
          'product': product,
          'entry': entry,
          'productName': product.name,
          'entryIndex': entryIndex,
        });
      }
    });
    list.sort(
      (a, b) => (b['entry'] as JournalEntry).date.compareTo(
        (a['entry'] as JournalEntry).date,
      ),
    );
    return list;
  }

  Future<void> _saveProcedureEntries() async {
    await AppPrefs.setString(
      'active_procedure_entries',
      jsonEncode(widget.activeProcedures.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> _saveSkincareEntries() async {
    final jsonMap = widget.skincareJournals.map(
      (key, value) =>
          MapEntry(key, value.map((entry) => entry.toJson()).toList()),
    );
    await AppPrefs.setString('skincare_journal_entries', jsonEncode(jsonMap));
  }

  String _formatJournalDate(DateTime date) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildEntryImage(String? path) {
    if (path == null || path.isEmpty) {
      return const SizedBox.shrink();
    }
    if (kIsWeb) {
      return Image.network(path, fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }

  Future<void> _showJournalEntryDetails(Map<String, dynamic> item) async {
    final entry = item['entry'] as JournalEntry;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                item['title'] as String,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: MyApp.roseGold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _formatJournalDate(entry.date),
                style: TextStyle(
                  color: MyApp.textBrown.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                ['😞', '😐', '🙂', '😊', '🥰'][entry.moodRating - 1],
                style: const TextStyle(fontSize: 34),
              ),
              if (entry.title.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                entry.content,
                style: const TextStyle(fontSize: 16, height: 1.6),
              ),
              if (entry.attachedImagePath != null &&
                  entry.attachedImagePath!.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Attached Photo',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: _buildEntryImage(entry.attachedImagePath),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _editJournalEntry(item);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyApp.roseGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Edit Entry'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyApp.textBrown,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editJournalEntry(Map<String, dynamic> item) async {
    final oldEntry = item['entry'] as JournalEntry;
    final titleController = TextEditingController(
      text: oldEntry.title == 'Journal Entry' ? '' : oldEntry.title,
    );
    final contentController = TextEditingController(text: oldEntry.content);
    int selectedMood = oldEntry.moodRating;
    String? attachedImagePath = oldEntry.attachedImagePath;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Journal Entry'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Notes about your skin...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('How does your skin feel today?'),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(5, (i) {
                    final emoji = ['😞', '😐', '🙂', '😊', '🥰'][i];
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedMood = i + 1),
                      child: Text(
                        emoji,
                        style: TextStyle(
                          fontSize: selectedMood == i + 1 ? 36 : 26,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Change Attached Photo'),
                  onPressed: () async {
                    final image = await _picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (image != null) {
                      setDialogState(() => attachedImagePath = image.path);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyApp.roseGold,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (attachedImagePath != null && attachedImagePath!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Attached: ${attachedImagePath!.split('/').last}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.goldShimmer,
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                final updatedEntry = JournalEntry(
                  date: oldEntry.date,
                  title: titleController.text.trim().isEmpty
                      ? 'Journal Entry'
                      : titleController.text.trim(),
                  content: contentController.text.trim(),
                  moodRating: selectedMood,
                  attachedImagePath: attachedImagePath,
                );

                if (updatedEntry.content.isEmpty) {
                  return;
                }

                if ((item['type'] as String) == 'procedure') {
                  final procedureIndex = item['procedureIndex'] as int;
                  final entryIndex = item['entryIndex'] as int;
                  widget
                          .activeProcedures[procedureIndex]
                          .journalEntries[entryIndex] =
                      updatedEntry;
                  await _saveProcedureEntries();
                } else {
                  final productName = item['productName'] as String;
                  final entryIndex = item['entryIndex'] as int;
                  final entries = widget.skincareJournals[productName];
                  if (entries != null && entryIndex < entries.length) {
                    entries[entryIndex] = updatedEntry;
                    await _saveSkincareEntries();
                  }
                }

                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                setState(() {});
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addNewEntry(bool isProcedure) async {
    if (isProcedure && widget.activeProcedures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a procedure first to journal it.')),
      );
      return;
    }
    if (!isProcedure && widget.trackedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Track at least one skincare product first.'),
        ),
      );
      return;
    }

    dynamic selectedItem;

    if (isProcedure) {
      selectedItem = await showModalBottomSheet<models.Procedure>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choose Procedure',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...widget.activeProcedures.map(
                (proc) => ListTile(
                  title: Text(proc.type),
                  onTap: () => Navigator.pop(ctx, proc),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      selectedItem = await showModalBottomSheet<TrackedProduct>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choose Skincare Product',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...widget.trackedProducts.map(
                (p) => ListTile(
                  title: Text('${p.brand} - ${p.name}'),
                  onTap: () => Navigator.pop(ctx, p),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (selectedItem == null || !mounted) return;

    // Journal form
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    int selectedMood = 3;
    String? attachedImagePath;

    final affirmations = [
      "My skin is healing beautifully.",
      "I am consistent and patient with my routine.",
      "Every day my skin feels stronger.",
      "I trust the process and love my skin.",
      "I am seeing real progress.",
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Padding(
          padding: MediaQuery.of(ctx).viewInsets + const EdgeInsets.all(24),
          child: SingleChildScrollView(
            controller: scrollController,
            child: StatefulBuilder(
              builder: (context, setModalState) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New ${isProcedure ? "Procedure" : "Skincare"} Entry',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('How does your skin feel today?'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(5, (i) {
                      final emoji = ['😞', '😐', '🙂', '😊', '🥰'][i];
                      return GestureDetector(
                        onTap: () => setModalState(() => selectedMood = i + 1),
                        child: Text(
                          emoji,
                          style: TextStyle(
                            fontSize: selectedMood == i + 1 ? 48 : 32,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: contentController,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Notes about your skin...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Quick Affirmation'),
                  DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Pick one'),
                    items: affirmations
                        .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) contentController.text += "\n\n💖 $val";
                    },
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Attach Photo or Scan'),
                    onPressed: () async {
                      final image = await _picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (image != null) {
                        setModalState(() => attachedImagePath = image.path);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.roseGold,
                    ),
                  ),
                  if (attachedImagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Attached: ${attachedImagePath!.split('/').last}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MyApp.goldShimmer,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () async {
                            final title = titleController.text.trim();
                            final content = contentController.text.trim();
                            if (content.isEmpty) return;

                            final newEntry = JournalEntry(
                              date: DateTime.now(),
                              title: title.isEmpty ? 'Journal Entry' : title,
                              content: content,
                              moodRating: selectedMood,
                              attachedImagePath: attachedImagePath,
                            );

                            if (isProcedure) {
                              final proc = selectedItem as models.Procedure;
                              proc.journalEntries.add(newEntry);
                              await _saveProcedureEntries();
                            } else {
                              final product = selectedItem as TrackedProduct;
                              final current =
                                  widget.skincareJournals[product.name] ?? [];
                              current.add(newEntry);
                              widget.skincareJournals[product.name] = current;
                              await _saveSkincareEntries();
                            }

                            if (mounted && ctx.mounted) {
                              Navigator.pop(ctx);
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Journal entry saved successfully!',
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Text('Save Entry'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = MyApp.textBrown;
    final procEntries = _procedureEntries;
    final skinEntries = _skincareEntries;
    final totalEntries = procEntries.length + skinEntries.length;
    final allDates = [
      ...procEntries.map((e) => (e['entry'] as JournalEntry).date),
      ...skinEntries.map((e) => (e['entry'] as JournalEntry).date),
    ]..sort((a, b) => b.compareTo(a));
    final latest = allDates.isEmpty ? null : allDates.first;

    return Scaffold(
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: 'Skin Journey Journal',
          eyebrow: 'Daily reflections',
          color: textColor,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero summary card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    MyApp.champagne.withValues(alpha: 0.95),
                    MyApp.roseGold.withValues(alpha: 0.18),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: MyApp.goldShimmer.withValues(alpha: 0.22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: MyApp.roseGold.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [MyApp.goldShimmer, MyApp.roseGold],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: MyApp.goldShimmer.withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Journal',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              totalEntries == 0
                                  ? 'Start logging how your skin feels each day.'
                                  : 'Reflect on your skin journey, one entry at a time.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: textColor.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildJournalStat(
                        'Entries',
                        '$totalEntries',
                        Icons.edit_note_rounded,
                      ),
                      const SizedBox(width: 10),
                      _buildJournalStat(
                        'Procedure',
                        '${procEntries.length}',
                        Icons.medical_services_outlined,
                      ),
                      const SizedBox(width: 10),
                      _buildJournalStat(
                        'Skincare',
                        '${skinEntries.length}',
                        Icons.spa_outlined,
                      ),
                    ],
                  ),
                  if (latest != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: MyApp.goldShimmer.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: textColor.withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Last entry · ${_formatJournalDate(latest)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: textColor.withValues(alpha: 0.80),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),

            const ClinicalSectionHeader(
              icon: Icons.medical_services_outlined,
              title: 'Procedure Entries',
              eyebrow: 'Recovery log',
            ),
            const SizedBox(height: 10),
            // Procedure entries section
            _buildJournalSection(
              icon: Icons.medical_services_outlined,
              title: 'Procedure Entries',
              expanded: _showProcedureEntries,
              onToggle: (v) => setState(() => _showProcedureEntries = v),
              addLabel: 'New Procedure Entry',
              onAdd: () => _addNewEntry(true),
              entries: procEntries,
              emptyIcon: Icons.edit_note_rounded,
              emptyText: 'No procedure entries yet',
              emptySub: 'Log how you feel after a treatment to track recovery.',
            ),

            const SizedBox(height: 22),

            const ClinicalSectionHeader(
              icon: Icons.spa_outlined,
              title: 'Skincare Entries',
              eyebrow: 'Routine reflections',
            ),
            const SizedBox(height: 10),
            // Skincare entries section
            _buildJournalSection(
              icon: Icons.spa_outlined,
              title: 'Skincare Entries',
              expanded: _showSkincareEntries,
              onToggle: (v) => setState(() => _showSkincareEntries = v),
              addLabel: 'New Skincare Entry',
              onAdd: () => _addNewEntry(false),
              entries: skinEntries,
              emptyIcon: Icons.spa_outlined,
              emptyText: 'No skincare entries yet',
              emptySub: 'Capture how a product is working for you over time.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJournalStat(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: MyApp.roseGold),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: MyApp.textBrown,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: MyApp.textBrown.withValues(alpha: 0.65),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJournalSection({
    required IconData icon,
    required String title,
    required bool expanded,
    required ValueChanged<bool> onToggle,
    required String addLabel,
    required VoidCallback onAdd,
    required List<Map<String, dynamic>> entries,
    required IconData emptyIcon,
    required String emptyText,
    required String emptySub,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: MyApp.roseGold.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => onToggle(!expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: MyApp.roseGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: MyApp.roseGold, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: MyApp.textBrown,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: MyApp.textBrown.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: expanded ? 0.5 : 0,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: MyApp.goldShimmer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: Text(
                    addLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyApp.roseGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 1,
                  ),
                ),
              ),
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            MyApp.roseGold.withValues(alpha: 0.13),
                            Colors.white.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(emptyIcon, color: MyApp.roseGold, size: 26),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      emptyText,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: MyApp.textBrown,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      emptySub,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: MyApp.textBrown.withValues(alpha: 0.65),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Column(
                  children: entries.map(_buildJournalEntryTile).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildJournalEntryTile(Map<String, dynamic> e) {
    final moodIndex = (e['mood'] as int).clamp(1, 5) - 1;
    final mood = ['😞', '😐', '🙂', '😊', '🥰'][moodIndex];
    final content = (e['content'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.18)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showJournalEntryDetails(e),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MyApp.champagne.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Text(mood, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e['title'],
                        style: TextStyle(
                          color: MyApp.textBrown,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e['subtitle'],
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.62),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MyApp.textBrown.withValues(alpha: 0.75),
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: MyApp.goldShimmer.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
