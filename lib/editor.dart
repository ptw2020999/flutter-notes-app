import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'main.dart';

// --- 编辑器页面 ---
class NoteEditorPage extends StatefulWidget {
  final Note? note;
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
  String _selectedCategory = '未分类';
  String? _imagePath;
  bool _isSaving = false;

  late final ImagePicker _imagePicker;

  @override
  void initState() {
    super.initState();
    _imagePicker = ImagePicker();

    if (widget.note != null) {
      _titleController.text = widget.note!.title;
      _selectedCategory = widget.note!.category;
      _imagePath = widget.note!.imagePath;
      _contentController.text = widget.note!.content;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _imagePath = image.path;
        });
      }
    } catch (e) {
      print('选择图片失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('选择图片失败')),
        );
      }
    }
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text;

    if (title.isEmpty && content.isEmpty && _imagePath == null) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final note = Note(
        id: widget.note?.id ?? 0,
        title: title.isEmpty ? "无标题" : title,
        content: content,
        category: _selectedCategory,
        imagePath: _imagePath,
        createdAt: widget.note?.createdAt,
        updatedAt: DateTime.now(),
      );

      if (widget.useLocalStorage) {
        if (widget.note == null) {
          await LocalStorage.addNote(note);
        } else {
          await LocalStorage.updateNote(note);
        }
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // 网络存储模式
      http.Response response;

      if (widget.note == null) {
        response = await http.post(
          Uri.parse(widget.baseUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(note.toJson()),
        ).timeout(const Duration(seconds: 5));
      } else {
        response = await http.put(
          Uri.parse("${widget.baseUrl}${widget.note!.id}"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(note.toJson()),
        ).timeout(const Duration(seconds: 5));
      }

      if (response.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      print("保存失败: $e");
      // 网络失败时尝试本地保存
      try {
        final note = Note(
          id: widget.note?.id ?? 0,
          title: title.isEmpty ? "无标题" : title,
          content: content,
          category: _selectedCategory,
          imagePath: _imagePath,
        );

        if (widget.note == null) {
          await LocalStorage.addNote(note);
        } else {
          await LocalStorage.updateNote(note);
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

            // 分类选择
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: '分类',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: CategoryManager.defaultCategories.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value!;
                  });
                },
              ),
            ),

            const SizedBox(height: 8),

            // 格式化工具栏
            _buildFormattingToolbar(),

            const Divider(height: 1),

            // 内容编辑器
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _contentController,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    hintText: "开始记录...",
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.black26),
                  ),
                ),
              ),
            ),

            // 多媒体工具栏
            _buildMultimediaToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormattingToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              // 简单的格式化提示
              final text = _contentController.text;
              final selection = _contentController.selection;
              final selectedText = selection.textInside(text);
              if (selectedText.isNotEmpty) {
                final formattedText = '**$selectedText**'; // 粗体标记
                _contentController.text = text.replaceRange(
                  selection.start,
                  selection.end,
                  formattedText,
                );
              }
            },
            icon: const Icon(Icons.format_bold),
            tooltip: '粗体',
          ),
          IconButton(
            onPressed: () {
              // 插入标题
              final text = _contentController.text;
              final selection = _contentController.selection;
              _contentController.text = '# 标题\n\n$text';
              _contentController.selection = selection;
            },
            icon: const Icon(Icons.title),
            tooltip: '标题',
          ),
          IconButton(
            onPressed: () {
              // 插入列表
              final text = _contentController.text;
              final selection = _contentController.selection;
              _contentController.text = '• 项目\n\n$text';
              _contentController.selection = selection;
            },
            icon: const Icon(Icons.format_list_bulleted),
            tooltip: '列表',
          ),
          IconButton(
            onPressed: () {
              // 插入分割线
              final text = _contentController.text;
              final selection = _contentController.selection;
              _contentController.text = '---\n\n$text';
              _contentController.selection = selection;
            },
            icon: const Icon(Icons.horizontal_rule),
            tooltip: '分割线',
          ),
        ],
      ),
    );
  }

  Widget _buildMultimediaToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          // 图片显示区域
          if (_imagePath != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_imagePath!),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 150,
                          width: double.infinity,
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.broken_image, size: 50),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _imagePath = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 工具按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('拍照'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade100,
                    foregroundColor: Colors.blue.shade700,
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('相册'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade100,
                    foregroundColor: Colors.green.shade700,
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '提示：点击工具栏按钮可快速格式化文本',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}