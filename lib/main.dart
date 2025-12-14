import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'editor.dart';

// --- 1. 数据模型 ---
class Note {
  final int id;
  final String title;
  final String content;
  final String category;
  final String? imagePath;
  final String? audioPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.category = '未分类',
    this.imagePath,
    this.audioPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      category: json['category'] ?? '未分类',
      imagePath: json['imagePath'],
      audioPath: json['audioPath'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category': category,
      'imagePath': imagePath,
      'audioPath': audioPath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

// --- 分类管理 ---
class CategoryManager {
  static const List<String> defaultCategories = [
    '未分类',
    '工作',
    '学习',
    '生活',
    '创意',
    '旅行',
    '健康',
    '财务',
    '项目',
  ];
}

// --- 本地存储管理 ---
class LocalStorage {
  static List<Note> _notes = [];
  static int _nextId = 1;
  static bool _initialized = false;

  static void _initializeSampleData() {
    if (_initialized) return;

    _notes = [
      Note(
        id: _nextId++,
        title: "欢迎使用灵感笔记 Pro",
        content: "这是一个功能强大的笔记应用，支持富文本编辑、图片、录音和分类管理。\n\n✨ 新功能特点：\n• 📝 富文本编辑器 - 支持字体、颜色、格式化\n• 📸 图片插入 - 拍照或从相册选择\n• 🎙️ 语音录制 - 记录语音备忘录\n• 📂 分类管理 - 整理你的笔记\n• 🎨 现代化UI - Material Design 3\n\n点击右下角的按钮开始创建你的第一条笔记吧！",
        category: "使用指南",
      ),
      Note(
        id: _nextId++,
        title: "富文本编辑器使用指南",
        content: "编辑器支持多种格式化选项：\n\n📝 文本格式：\n• 粗体、斜体、下划线\n• 标题级别 (H1-H6)\n• 文本颜色和背景色\n• 文本对齐方式\n\n📋 列表功能：\n• 有序列表和无序列表\n• 缩进和取消缩进\n\n🔗 其他功能：\n• 引用块\n• 代码块\n• 链接插入\n\n点击任意笔记卡片开始体验吧！",
        category: "使用指南",
      ),
      Note(
        id: _nextId++,
        title: "多媒体功能说明",
        content: "📸 图片功能：\n• 点击相机图标拍照\n• 点击相册图标选择图片\n• 支持JPG、PNG等格式\n\n🎙️ 录音功能：\n• 点击录音按钮开始录制\n• 再次点击停止录制\n• 点击播放按钮听取录音\n\n📂 分类管理：\n• 从预设分类中选择\n• 帮助你更好地组织笔记\n\n所有数据都保存在本地，确保你的隐私安全！",
        category: "使用指南",
      ),
    ];
    _initialized = true;
  }

  static Future<List<Note>> getNotes({String? category}) async {
    _initializeSampleData();
    await Future.delayed(const Duration(milliseconds: 300));

    List<Note> notes = _notes;
    if (category != null && category.isNotEmpty) {
      notes = notes.where((note) => note.category == category).toList();
    }
    return notes;
  }

  static Future<Note> addNote(Note note) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final newNote = Note(
      id: _nextId++,
      title: note.title,
      content: note.content,
      category: note.category,
      imagePath: note.imagePath,
      audioPath: note.audioPath,
    );
    _notes.insert(0, newNote);
    return newNote;
  }

  static Future<Note> updateNote(Note note) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      final updatedNote = Note(
        id: note.id,
        title: note.title,
        content: note.content,
        category: note.category,
        imagePath: note.imagePath,
        audioPath: note.audioPath,
        createdAt: _notes[index].createdAt,
        updatedAt: DateTime.now(),
      );
      _notes[index] = updatedNote;
      return updatedNote;
    }
    throw Exception('Note not found');
  }

  static Future<bool> deleteNote(int id) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _notes.removeWhere((note) => note.id == id);
    return true;
  }

  static Future<List<String>> getCategories() async {
    _initializeSampleData();
    await Future.delayed(const Duration(milliseconds: 100));
    final categories = CategoryManager.defaultCategories.toList();
    final noteCategories = _notes.map((note) => note.category).toSet();
    categories.addAll(noteCategories);
    categories.remove('未分类');
    categories.sort();
    return ['未分类', ...categories];
  }
}

// --- 2. 主入口 ---
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '灵感笔记 Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006C70),
          brightness: Brightness.light,
        ),
      ),
      home: const NoteListPage(),
    );
  }
}

// --- 3. 笔记列表页面 ---
class NoteListPage extends StatefulWidget {
  const NoteListPage({super.key});

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  final String baseUrl = "http://10.0.2.2:8000/notes/";
  List<Note> _notes = [];
  List<String> _categories = [];
  String _selectedCategory = '';
  bool _isLoading = true;
  bool _useLocalStorage = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    await Future.wait([
      _fetchNotes(),
      _fetchCategories(),
    ]);
  }

  Future<void> _fetchNotes() async {
    setState(() => _isLoading = true);

    if (_useLocalStorage) {
      try {
        final notes = await LocalStorage.getNotes(category: _selectedCategory);
        setState(() {
          _notes = notes;
          _isLoading = false;
        });
      } catch (e) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _useLocalStorage = true;
          throw TimeoutException('连接超时，切换到本地模式');
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> noteJson = jsonDecode(
          utf8.decode(response.bodyBytes),
        );
        setState(() {
          _notes = noteJson.map((json) => Note.fromJson(json)).toList();
          _notes = _notes.reversed.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print("网络连接失败，切换到本地存储: $e");
      _useLocalStorage = true;
      _fetchNotes();
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final categories = await LocalStorage.getCategories();
      setState(() {
        _categories = categories;
      });
    } catch (e) {
      print("获取分类失败: $e");
    }
  }

  Future<void> _deleteNote(int id) async {
    bool success = false;

    if (_useLocalStorage) {
      try {
        success = await LocalStorage.deleteNote(id);
      } catch (e) {
        print("本地删除失败: $e");
      }
    } else {
      try {
        final response = await http.delete(
          Uri.parse("$baseUrl$id"),
        ).timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            throw TimeoutException('连接超时');
          },
        );
        if (response.statusCode == 200) {
          success = true;
        }
      } catch (e) {
        print("网络删除失败，尝试本地删除: $e");
        try {
          success = await LocalStorage.deleteNote(id);
          if (success && !_useLocalStorage) {
            _useLocalStorage = true;
            _notes.removeWhere((note) => note.id == id);
          }
        } catch (localError) {
          print("本地删除也失败: $localError");
        }
      }
    }

    if (success) {
      _fetchData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_useLocalStorage ? "已删除 (本地模式)" : "已删除"),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("删除失败")),
        );
      }
    }
  }

  void _goToEditor({Note? note}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteEditorPage(
          note: note,
          useLocalStorage: _useLocalStorage,
          baseUrl: baseUrl,
        ),
      ),
    );

    if (result == true) {
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          "📒 灵感笔记 Pro",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (category) {
              setState(() {
                _selectedCategory = category;
              });
              _fetchNotes();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: '',
                child: Text('全部分类'),
              ),
              ..._categories.map((category) => PopupMenuItem(
                value: category,
                child: Text(category),
              )),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_selectedCategory.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Text(
                    '分类: $_selectedCategory',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      setState(() {
                        _selectedCategory = '';
                      });
                      _fetchNotes();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.note_add_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _selectedCategory.isNotEmpty
                                  ? '该分类下还没有笔记'
                                  : "还没有笔记，点击右下角创建",
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12.0),
                        itemCount: _notes.length,
                        itemBuilder: (context, index) {
                          final note = _notes[index];
                          return NoteCard(
                            note: note,
                            onTap: () => _goToEditor(note: note),
                            onDelete: () => _deleteNote(note.id),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _goToEditor(),
        elevation: 4,
        label: const Text("新笔记", style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.edit),
      ),
    );
  }
}

// --- 笔记卡片组件 ---
class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (note.category != '未分类')
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              note.category,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (note.imagePath != null)
                        const Icon(Icons.image, size: 16, color: Colors.blue),
                      if (note.audioPath != null)
                        const Icon(Icons.mic, size: 16, color: Colors.red),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: onDelete,
                        child: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                note.content.length > 100
                    ? '${note.content.substring(0, 100)}...'
                    : note.content,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _formatDate(note.updatedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }
}