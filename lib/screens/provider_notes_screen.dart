import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';
import '../widgets/luxe_loading_view.dart';
import '../utils/app_prefs.dart';

/// A single clinical note recorded by the user against a procedure.
///
/// Stored in SharedPreferences under [_ProviderNotesStore._key] as a JSON
/// array. Each note is scoped to a [procedureId] so notes don't leak
/// between procedures.
class ProviderNote {
  final String id;
  final String procedureId;
  final DateTime date;
  final String title; // optional — empty string when omitted
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProviderNote({
    required this.id,
    required this.procedureId,
    required this.date,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  ProviderNote copyWith({
    DateTime? date,
    String? title,
    String? content,
    DateTime? updatedAt,
  }) {
    return ProviderNote(
      id: id,
      procedureId: procedureId,
      date: date ?? this.date,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'procedureId': procedureId,
    'date': date.toIso8601String(),
    'title': title,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ProviderNote.fromJson(Map<String, dynamic> json) => ProviderNote(
    id: json['id'] as String,
    procedureId: (json['procedureId'] ?? '').toString(),
    date: DateTime.parse(json['date'] as String),
    title: (json['title'] ?? '').toString(),
    content: (json['content'] ?? '').toString(),
    createdAt: DateTime.parse((json['createdAt'] ?? json['date']) as String),
    updatedAt: DateTime.parse((json['updatedAt'] ?? json['date']) as String),
  );
}

class _ProviderNotesStore {
  static const _key = 'provider_notes_v1';

  static Future<List<ProviderNote>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) => ProviderNote.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveAll(List<ProviderNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(notes.map((n) => n.toJson()).toList()),
    );
  }
}

/// Dedicated screen surfaced from the Premium Recovery Hub's "Provider
/// Notes" card. Scopes notes to the currently active procedure when one
/// is selected. Falls back to a global note book when none is active.
class ProviderNotesScreen extends StatefulWidget {
  /// Optional override for the procedure id to scope notes to. When null
  /// the screen reads the active procedure id from [AppPrefs].
  final String? procedureId;

  /// Optional display label for the procedure header. When null the
  /// screen resolves the label from the stored procedure entries.
  final String? procedureLabel;

  const ProviderNotesScreen({super.key, this.procedureId, this.procedureLabel});

  @override
  State<ProviderNotesScreen> createState() => _ProviderNotesScreenState();
}

class _ProviderNotesScreenState extends State<ProviderNotesScreen> {
  bool _loading = true;
  String? _procedureId;
  String? _procedureLabel;
  List<ProviderNote> _notes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    String? procId = widget.procedureId;
    String? procLabel = widget.procedureLabel;
    List<ProviderNote> scoped = const [];

    try {
      // Guard every async hop with a timeout so a stalled storage read can
      // never leave the screen spinning forever.
      if (procId == null || procId.isEmpty) {
        procId = await AppPrefs.getSelectedProcedureIdOrNull().timeout(
          const Duration(seconds: 6),
          onTimeout: () => null,
        );
      }
      if ((procLabel == null || procLabel.isEmpty) &&
          procId != null &&
          procId.isNotEmpty) {
        final entries = await AppPrefs.getProcedureEntries().timeout(
          const Duration(seconds: 6),
          onTimeout: () => const <Map<String, dynamic>>[],
        );
        for (final raw in entries) {
          final id = (raw['id'] ?? raw['procedureId'] ?? '').toString().trim();
          if (id == procId.trim()) {
            final label = (raw['type'] ?? raw['name'] ?? '').toString().trim();
            if (label.isNotEmpty) procLabel = label;
            break;
          }
        }
      }

      final all = await _ProviderNotesStore.loadAll().timeout(
        const Duration(seconds: 6),
        onTimeout: () => const <ProviderNote>[],
      );
      scoped = (procId == null || procId.isEmpty)
          ? all
          : all.where((n) => n.procedureId == procId).toList();
      scoped.sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {
      // Fall through to an empty (but resolved) state rather than hanging.
      scoped = const [];
    }

    if (!mounted) return;
    setState(() {
      _procedureId = procId;
      _procedureLabel = procLabel;
      _notes = scoped;
      _loading = false;
    });
  }

  Future<void> _persist(List<ProviderNote> nextScoped) async {
    final all = await _ProviderNotesStore.loadAll();
    final others = (_procedureId == null || _procedureId!.isEmpty)
        ? const <ProviderNote>[]
        : all.where((n) => n.procedureId != _procedureId).toList();
    await _ProviderNotesStore.saveAll([...others, ...nextScoped]);
  }

  Future<void> _openEditor({ProviderNote? editing}) async {
    final result = await showModalBottomSheet<ProviderNote>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          _NoteEditorSheet(existing: editing, procedureId: _procedureId ?? ''),
    );
    if (result == null || !mounted) return;
    final next = [..._notes];
    final idx = next.indexWhere((n) => n.id == result.id);
    if (idx >= 0) {
      next[idx] = result;
    } else {
      next.add(result);
    }
    next.sort((a, b) => b.date.compareTo(a.date));
    setState(() => _notes = next);
    await _persist(next);
  }

  Future<void> _deleteNote(ProviderNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MyApp.champagne,
        title: const Text('Delete Note?'),
        content: Text(
          note.title.isNotEmpty
              ? 'Delete "${note.title}"? This cannot be undone.'
              : 'Delete this note? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final next = _notes.where((n) => n.id != note.id).toList();
    setState(() => _notes = next);
    await _persist(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.textBrown,
        title: ClinicalAppBarTitle(
          title: 'Provider Notes',
          eyebrow: 'Care records',
          color: MyApp.textBrown,
        ),
        centerTitle: true,
      ),
      floatingActionButton: _notes.isEmpty
          ? null
          : Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: MyApp.goldShimmer.withValues(alpha: 0.42),
                    blurRadius: 22,
                    spreadRadius: 1,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: () => _openEditor(),
                backgroundColor: MyApp.goldShimmer,
                foregroundColor: AppColors.onChampagneGold,
                elevation: 0,
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'New Note',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
      body: SafeArea(
        child: _loading
            ? const LuxeLoadingView(label: 'Loading provider notes…')
            : _notes.isEmpty
            ? _buildEmptyState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: ClinicalSectionHeader(
                      icon: Icons.notes_outlined,
                      title: 'Saved Notes',
                      eyebrow: 'Care team records',
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemBuilder: (context, index) =>
                          _buildNoteCard(_notes[index]),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemCount: _notes.length,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    final label = _procedureLabel ?? 'All Procedures';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: MyApp.goldShimmer.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: MyApp.goldShimmer.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.note_alt_outlined,
                  size: 14,
                  color: MyApp.goldShimmer,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: MyApp.goldShimmer,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_notes.length} note${_notes.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: MyApp.textBrown.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(ProviderNote note) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final d = note.date;
    final dateLabel = '${months[d.month - 1]} ${d.day}, ${d.year}';
    return Material(
      color: MyApp.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openEditor(editing: note),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: MyApp.goldShimmer.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 44,
                margin: const EdgeInsets.only(right: 12, top: 2),
                decoration: BoxDecoration(
                  color: MyApp.goldShimmer,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            note.title.isNotEmpty
                                ? note.title
                                : 'Provider Note',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: MyApp.textBrown,
                            ),
                          ),
                        ),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: MyApp.textBrown.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      note.content,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: MyApp.textBrown.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Note actions',
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: MyApp.textBrown.withValues(alpha: 0.55),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    _openEditor(editing: note);
                  } else if (value == 'delete') {
                    _deleteNote(note);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Concentric champagne-gold halo around the icon.
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: MyApp.goldShimmer.withValues(alpha: 0.14),
                  width: 1.2,
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MyApp.goldShimmer.withValues(alpha: 0.22),
                    width: 1.1,
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MyApp.goldShimmer.withValues(alpha: 0.12),
                    boxShadow: [
                      BoxShadow(
                        color: MyApp.goldShimmer.withValues(alpha: 0.22),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.note_alt_outlined,
                    size: 40,
                    color: MyApp.goldShimmer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No provider notes yet',
              style: MyApp.sectionTitleStyle().copyWith(fontSize: 19),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _procedureLabel == null
                  ? 'Capture surgeon instructions, follow-up details, and care reminders. They will appear here.'
                  : 'Capture surgeon instructions, follow-up details, and care reminders for $_procedureLabel.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: MyApp.textBrown.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 22),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: MyApp.goldShimmer.withValues(alpha: 0.36),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add First Note'),
                style: FilledButton.styleFrom(
                  backgroundColor: MyApp.goldShimmer,
                  foregroundColor: AppColors.onChampagneGold,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteEditorSheet extends StatefulWidget {
  final ProviderNote? existing;
  final String procedureId;

  const _NoteEditorSheet({this.existing, required this.procedureId});

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _contentCtrl = TextEditingController(
    text: widget.existing?.content ?? '',
  );
  late DateTime _date = widget.existing?.date ?? DateTime.now();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the note content before saving.'),
        ),
      );
      return;
    }
    final now = DateTime.now();
    final note = widget.existing == null
        ? ProviderNote(
            id: 'note_${now.microsecondsSinceEpoch}',
            procedureId: widget.procedureId,
            date: _date,
            title: _titleCtrl.text.trim(),
            content: content,
            createdAt: now,
            updatedAt: now,
          )
        : widget.existing!.copyWith(
            date: _date,
            title: _titleCtrl.text.trim(),
            content: content,
          );
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateLabel = '${months[_date.month - 1]} ${_date.day}, ${_date.year}';
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: BoxDecoration(
          color: MyApp.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MyApp.textBrown.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.existing == null ? 'New Note' : 'Edit Note',
                style: MyApp.sectionTitleStyle().copyWith(fontSize: 18),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Title (optional)',
                  hintText: 'e.g. Post-op week 2 check-in',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: MyApp.textBrown.withValues(alpha: 0.65),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: MyApp.textBrown,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 12,
                          color: MyApp.goldShimmer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentCtrl,
                minLines: 6,
                maxLines: 12,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Note',
                  hintText:
                      'Surgeon instructions, follow-up reminders, observations...',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: MyApp.goldShimmer,
                        foregroundColor: AppColors.onChampagneGold,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Note',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
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
}
