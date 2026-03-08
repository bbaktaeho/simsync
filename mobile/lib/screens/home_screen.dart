import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../note_store.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = NoteStore();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _scrollController = ScrollController();

  DateTime _selectedDate = DateTime.now();
  int _calYear = DateTime.now().year;
  int _calMonth = DateTime.now().month;

  List<NoteMeta> _notes = [];
  Set<String> _monthDates = {};
  String _currentNoteId = '';
  String _status = '';
  bool _isPreview = false;
  bool _calendarExpanded = true;
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    _loadMonth();
    _loadNotes();
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _selectedDateStr => _formatDate(_selectedDate);

  Future<void> _loadMonth() async {
    final dates = await _store.getMonthNotes(_calYear, _calMonth);
    setState(() => _monthDates = dates.toSet());
  }

  Future<void> _loadNotes() async {
    final notes = await _store.listNotesByDate(_selectedDateStr);
    setState(() => _notes = notes);
  }

  Future<void> _selectDate(DateTime date) async {
    setState(() {
      _selectedDate = date;
      _currentNoteId = '';
      _titleController.clear();
      _contentController.clear();
      _status = '';
      _isPreview = false;
    });
    await _loadNotes();
  }

  Future<void> _loadNote(String id) async {
    final note = await _store.loadNote(_selectedDateStr, id);
    setState(() {
      _currentNoteId = note.id;
      _titleController.text = note.title;
      _contentController.text = note.content;
      _isPreview = false;
      _status = '';
    });
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim().isEmpty ? 'Untitled' : _titleController.text.trim();
    final note = await _store.saveNote(_selectedDateStr, _currentNoteId, title, _contentController.text);
    setState(() {
      _currentNoteId = note.id;
      _status = 'Saved at ${TimeOfDay.now().format(context)}';
    });
    _loadNotes();
    _loadMonth();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), _saveNote);
  }

  Future<void> _deleteNote(String id) async {
    await _store.deleteNote(_selectedDateStr, id);
    if (_currentNoteId == id) {
      setState(() {
        _currentNoteId = '';
        _titleController.clear();
        _contentController.clear();
        _status = '';
      });
    }
    _loadNotes();
    _loadMonth();
  }

  void _newNote() {
    setState(() {
      _currentNoteId = '';
      _titleController.clear();
      _contentController.clear();
      _isPreview = false;
      _status = '';
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('SimSync', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        actions: [
          IconButton(
            icon: Icon(
              _calendarExpanded ? Icons.calendar_month : Icons.calendar_month_outlined,
              size: 20,
              color: _calendarExpanded ? const Color(0xFF569CD6) : const Color(0xFF888888),
            ),
            onPressed: () => setState(() => _calendarExpanded = !_calendarExpanded),
            tooltip: _calendarExpanded ? 'Hide calendar' : 'Show calendar',
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            child: const Text('Logout', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Calendar (collapsible)
            AnimatedCrossFade(
              firstChild: _buildCalendar(),
              secondChild: _buildCalendarCollapsed(),
              crossFadeState: _calendarExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 200),
            ),
            const Divider(height: 1),
            // Note list
            _buildNoteList(),
            const Divider(height: 1),
            // Editor (takes remaining space, scrollable with keyboard)
            Expanded(child: _buildEditor()),
            _buildStatusBar(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: _newNote,
        backgroundColor: const Color(0xFF0E639C),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildCalendarCollapsed() {
    final monthNames = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                _calMonth--;
                if (_calMonth < 1) { _calMonth = 12; _calYear--; }
              });
              _loadMonth();
            },
          ),
          const SizedBox(width: 8),
          Text('${monthNames[_calMonth]} $_calYear',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                _calMonth++;
                if (_calMonth > 12) { _calMonth = 1; _calYear++; }
              });
              _loadMonth();
            },
          ),
          const Spacer(),
          Text(_selectedDateStr, style: const TextStyle(fontSize: 13, color: Color(0xFF569CD6))),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    final monthNames = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    final firstDay = DateTime(_calYear, _calMonth, 1);
    final daysInMonth = DateTime(_calYear, _calMonth + 1, 0).day;
    final startOffset = (firstDay.weekday - 1) % 7;
    final today = DateTime.now();
    final todayStr = _formatDate(today);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: () {
                  setState(() {
                    _calMonth--;
                    if (_calMonth < 1) { _calMonth = 12; _calYear--; }
                  });
                  _loadMonth();
                },
              ),
              Text('${monthNames[_calMonth]} $_calYear',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: () {
                  setState(() {
                    _calMonth++;
                    if (_calMonth > 12) { _calMonth = 1; _calYear++; }
                  });
                  _loadMonth();
                },
              ),
            ],
          ),
          Row(
            children: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d, style: const TextStyle(fontSize: 11, color: Color(0xFF666666), fontWeight: FontWeight.w600)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, childAspectRatio: 1.2,
            ),
            itemCount: startOffset + daysInMonth,
            itemBuilder: (context, index) {
              if (index < startOffset) return const SizedBox();
              final day = index - startOffset + 1;
              final dateStr = '$_calYear-${_calMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final isToday = dateStr == todayStr;
              final isSelected = dateStr == _selectedDateStr;
              final hasNotes = _monthDates.contains(dateStr);

              return GestureDetector(
                onTap: () => _selectDate(DateTime(_calYear, _calMonth, day)),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF0E639C) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: (isToday || isSelected) ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : isToday ? const Color(0xFF569CD6) : const Color(0xFFD4D4D4),
                        ),
                      ),
                      if (hasNotes)
                        Container(
                          width: 4, height: 4, margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? Colors.white : const Color(0xFF569CD6),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoteList() {
    return SizedBox(
      height: _notes.isEmpty ? 48 : 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Notes — $_selectedDateStr',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF888888), fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _newNote,
                  child: const Icon(Icons.add, size: 18, color: Color(0xFF569CD6)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _notes.isEmpty
                ? const Center(child: Text('No notes', style: TextStyle(color: Color(0xFF666666), fontSize: 13)))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _notes.length,
                    itemBuilder: (context, index) {
                      final note = _notes[index];
                      final isActive = note.id == _currentNoteId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => _loadNote(note.id),
                          onLongPress: () => _deleteNote(note.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isActive ? const Color(0xFF37373D) : const Color(0xFF2A2D2E),
                              borderRadius: BorderRadius.circular(6),
                              border: isActive ? Border.all(color: const Color(0xFF569CD6), width: 1) : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (note.isDefault)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.circle, size: 6, color: Color(0xFF569CD6)),
                                  ),
                                Text(
                                  note.title.length > 16 ? '${note.title.substring(0, 16)}...' : note.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isActive ? const Color(0xFFD4D4D4) : const Color(0xFF999999),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _titleController,
            onChanged: (_) => _scheduleAutoSave(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFE0E0E0)),
            decoration: const InputDecoration(
              hintText: 'Note title...',
              hintStyle: TextStyle(color: Color(0xFF666666)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        // Edit / Preview tabs
        Row(
          children: [
            _buildTab('Edit', !_isPreview, () => setState(() => _isPreview = false)),
            _buildTab('Preview', _isPreview, () => setState(() => _isPreview = true)),
          ],
        ),
        // Content area
        Expanded(
          child: _isPreview
              ? Markdown(
                  data: _contentController.text,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 14, height: 1.6),
                    h1: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 24, fontWeight: FontWeight.bold),
                    h2: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 20, fontWeight: FontWeight.bold),
                    h3: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 16, fontWeight: FontWeight.bold),
                    code: TextStyle(
                      color: const Color(0xFFD4D4D4),
                      backgroundColor: const Color(0xFF2D2D2D),
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                )
              : Scrollbar(
                  child: TextField(
                    controller: _contentController,
                    focusNode: _contentFocusNode,
                    onChanged: (_) => _scheduleAutoSave(),
                    maxLines: null,
                    expands: true,
                    scrollController: _scrollController,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 14, color: Color(0xFFD4D4D4), height: 1.6,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Write your markdown here...',
                      hintStyle: TextStyle(color: Color(0xFF555555)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTab(String label, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: isActive ? const Color(0xFF0E639C) : Colors.transparent, width: 2)),
          ),
          child: Center(child: Text(label, style: TextStyle(
            fontSize: 13,
            color: isActive ? const Color(0xFFD4D4D4) : const Color(0xFF666666),
          ))),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF3C3C3C))),
      ),
      child: Text(_status, style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
    );
  }
}
