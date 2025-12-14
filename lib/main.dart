import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:math';

// --- 1. 数据模型 ---
class Note {
  final int id;
  final String title;
  final String content;

  Note({required this.id, required this.title, required this.content});

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(id: json['id'], title: json['title'], content: json['content']);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
    };
  }
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
        title: "欢迎使用灵感笔记",
        content: "这是一个简单的笔记应用，支持创建、编辑和删除笔记。\n\n功能特点：\n• 简洁的界面设计\n• 流畅的用户体验\n• 本地数据存储\n\n点击右下角的按钮开始创建你的第一条笔记吧！",
      ),
      Note(
        id: _nextId++,
        title: "使用提示",
        content: "• 点击卡片可以编辑笔记\n• 点击右上角的垃圾桶图标可以删除笔记\n• 长按卡片可以查看更多选项\n\n当前运行在本地模式下，数据保存在设备内存中。",
      ),
      Note(
        id: _nextId++,
        title: "关于网络模式",
        content: "当后端服务器可用时，应用会自动切换到网络模式，数据将保存在服务器上。\n\n如果网络连接失败，应用会自动降级到本地模式，确保数据不会丢失。",
      ),
    ];
    _initialized = true;
  }

  static Future<List<Note>> getNotes() async {
    // 初始化示例数据
    _initializeSampleData();
    // 模拟网络延迟
    await Future.delayed(const Duration(milliseconds: 300));
    return _notes;
  }

  static Future<Note> addNote(String title, String content) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final note = Note(id: _nextId++, title: title, content: content);
    _notes.insert(0, note); // 插入到开头
    return note;
  }

  static Future<Note> updateNote(int id, String title, String content) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _notes.indexWhere((note) => note.id == id);
    if (index != -1) {
      _notes[index] = Note(id: id, title: title, content: content);
      return _notes[index];
    }
    throw Exception('Note not found');
  }

  static Future<bool> deleteNote(int id) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _notes.removeWhere((note) => note.id == id);
    return true;
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
  // ⚠️ 真机调试请把 10.0.2.2 改为电脑 IP
  final String baseUrl = "http://10.0.2.2:8000/notes/";
  List<Note> _notes = [];
  bool _isLoading = true;
  bool _useLocalStorage = false;

  @override
  void initState() {
    super.initState();
    _fetchNotes();
  }

  // 获取列表
  Future<void> _fetchNotes() async {
    setState(() => _isLoading = true);

    if (_useLocalStorage) {
      try {
        final notes = await LocalStorage.getNotes();
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
          // 超时后切换到本地存储
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
      // 重新获取本地数据
      _fetchNotes();
    }
  }

  // 删除笔记
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
        // 网络失败时尝试本地删除
        try {
          success = await LocalStorage.deleteNote(id);
          if (success && !_useLocalStorage) {
            // 如果本地删除成功，切换到本地模式
            _useLocalStorage = true;
            // 从本地列表中移除
            _notes.removeWhere((note) => note.id == id);
          }
        } catch (localError) {
          print("本地删除也失败: $localError");
        }
      }
    }

    if (success) {
      _fetchNotes(); // 删除成功后刷新
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

  // 跳转到编辑器（新增或修改）
  void _goToEditor({Note? note}) async {
    // 等待编辑器页面返回结果
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

    // 如果返回 true，说明保存了，需要刷新列表
    if (result == true) {
      _fetchNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // 浅灰背景
      appBar: AppBar(
        title: const Text(
          "📒 灵感笔记",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: _notes.isEmpty
                  ? Center(
                      child: Text(
                        "还没有笔记，点击右下角创建",
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _notes.length,
                      itemBuilder: (context, index) {
                        final note = _notes[index];
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
                            // ✨ 点击卡片 -> 进入编辑模式
                            onTap: () => _goToEditor(note: note),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          note.title,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _deleteNote(note.id),
                                        child: Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    note.content,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      height: 1.5,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _goToEditor(), // 新增模式
        elevation: 4,
        label: const Text("新笔记", style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.edit),
      ),
    );
  }
}

// --- 4. 沉浸式编辑器页面 (核心功能) ---
class NoteEditorPage extends StatefulWidget {
  final Note? note; // 接收传过来的笔记
  final bool useLocalStorage;
  final String baseUrl;

  const NoteEditorPage({
    super.key,
    this.note,
    required this.useLocalStorage,
    required this.baseUrl,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // 如果是修改模式，先把原来的字填进去
    if (widget.note != null) {
      _titleController.text = widget.note!.title;
      _contentController.text = widget.note!.content;
    }
  }

  // 保存逻辑
  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      Navigator.pop(context); // 没写东西直接退出
      return;
    }

    setState(() => _isSaving = true);

    if (widget.useLocalStorage) {
      // 本地存储模式
      try {
        if (widget.note == null) {
          // 新增
          await LocalStorage.addNote(
            title.isEmpty ? "无标题" : title,
            content,
          );
        } else {
          // 修改
          await LocalStorage.updateNote(
            widget.note!.id,
            title.isEmpty ? "无标题" : title,
            content,
          );
        }
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        print("本地保存失败: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("保存失败")),
          );
          setState(() => _isSaving = false);
        }
      }
      return;
    }

    // 网络存储模式
    try {
      http.Response response;

      if (widget.note == null) {
        // --- 新增 (POST) ---
        response = await http.post(
          Uri.parse(widget.baseUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "title": title.isEmpty ? "无标题" : title,
            "content": content,
          }),
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('连接超时');
          },
        );
      } else {
        // --- 修改 (PUT) ---
        response = await http.put(
          Uri.parse("${widget.baseUrl}${widget.note!.id}"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "title": title.isEmpty ? "无标题" : title,
            "content": content,
          }),
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('连接超时');
          },
        );
      }

      if (response.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      print("网络保存失败，尝试本地保存: $e");
      // 网络失败时尝试本地保存
      try {
        if (widget.note == null) {
          await LocalStorage.addNote(
            title.isEmpty ? "无标题" : title,
            content,
          );
        } else {
          await LocalStorage.updateNote(
            widget.note!.id,
            title.isEmpty ? "无标题" : title,
            content,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("已保存到本地")),
          );
          Navigator.pop(context, true);
        }
      } catch (localError) {
        print("本地保存也失败: $localError");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("保存失败")),
          );
          setState(() => _isSaving = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // 纯白沉浸背景
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          _isSaving
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _saveNote,
                  child: const Text(
                    "完成",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 标题输入
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: TextField(
                controller: _titleController,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: "标题",
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.black26),
                ),
              ),
            ),
            const Divider(height: 1),
            // 正文输入 (自适应高度)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: TextField(
                  controller: _contentController,
                  style: const TextStyle(fontSize: 17, height: 1.5),
                  maxLines: null, // 允许无限换行
                  expands: true, // 撑满屏幕
                  decoration: const InputDecoration(
                    hintText: "开始记录...",
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.black26),
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
