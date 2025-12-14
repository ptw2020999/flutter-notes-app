import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'main.dart';

// --- 富文本编辑器页面 ---
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
  final quill.QuillController _quillController = quill.QuillController.basic();
  String _selectedCategory = '未分类';
  String? _imagePath;
  String? _audioPath;
  bool _isSaving = false;
  bool _isRecording = false;
  bool _isPlaying = false;
  Duration _recordingDuration = Duration.zero;
  Duration _position = Duration.zero;
  Duration? _duration;

  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;
  late final ImagePicker _imagePicker;
  Timer? _recordingTimer;
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();
    _imagePicker = ImagePicker();

    if (widget.note != null) {
      _titleController.text = widget.note!.title;
      _selectedCategory = widget.note!.category;
      _imagePath = widget.note!.imagePath;
      _audioPath = widget.note!.audioPath;

      // 设置富文本内容
      if (widget.note!.content.isNotEmpty) {
        try {
          final doc = quill.Document.fromJson(jsonDecode(widget.note!.content));
          _quillController.document = doc;
        } catch (e) {
          // 如果不是JSON格式，作为纯文本处理
          _quillController.document.insert(0, widget.note!.content);
        }
      }
    }

    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      setState(() {
        _position = position;
      });
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() {
        _duration = duration;
      });
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _positionSubscription?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
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

  Future<void> _startRecording() async {
    try {
      // 请求录音权限
      final hasPermission = await _requestPermission(Permission.microphone);
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要录音权限')),
          );
        }
        return;
      }

      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'recording_${const Uuid().v4()}.m4a';
      final filePath = '${directory.path}/$fileName';

      // 开始录音
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      // 开始计时
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration = Duration(seconds: _recordingDuration.inSeconds + 1);
        });
      });

    } catch (e) {
      print('开始录音失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('开始录音失败')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();

      setState(() {
        _isRecording = false;
        _audioPath = path;
        _recordingDuration = Duration.zero;
      });

    } catch (e) {
      print('停止录音失败: $e');
    }
  }

  Future<void> _playRecording() async {
    if (_audioPath == null) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.setSource(DeviceFileSource(_audioPath!));
        await _audioPlayer.resume();
      }
    } catch (e) {
      print('播放录音失败: $e');
    }
  }

  Future<bool> _requestPermission(Permission permission) async {
    final status = await permission.request();
    return status.isGranted;
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = jsonEncode(_quillController.document.toDelta().toJson());

    if (title.isEmpty && content.isEmpty && _imagePath == null && _audioPath == null) {
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
        audioPath: _audioPath,
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
          audioPath: _audioPath,
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
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

            // 富文本编辑器工具栏
            quill.QuillToolbar.basic(
              controller: _quillController,
            ),

            const Divider(height: 1),

            // 富文本编辑器
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: quill.QuillEditor(
                  controller: _quillController,
                  scrollController: ScrollController(),
                  focusNode: FocusNode(),
                  readOnly: false,
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

          // 录音显示和控制区域
          if (_audioPath != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _playRecording,
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.red,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '录音',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        _duration != null
                            ? _formatDuration(_duration!)
                            : '00:00',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _audioPath = null;
                      });
                    },
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

          // 录音状态显示
          if (_isRecording)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '录音中... ${_formatDuration(_recordingDuration)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
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
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? '停止' : '录音'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording
                        ? Colors.red.shade100
                        : Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}