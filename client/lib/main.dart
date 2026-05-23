// RemoteWindow Client — 매장 PC 특정 윈도우 실시간 모니터링/제어
// Sprint 2 PoC: 서버 주소 입력 → 윈도우 목록 → 스트리밍 + 탭 = 클릭

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'updater.dart';
import 'upload.dart';

void main() => runApp(const RemoteWindowApp());

class RemoteWindowApp extends StatelessWidget {
  const RemoteWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RemoteWindow',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF101216),
      ),
      home: const ConnectPage(),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 1) 연결 화면 — 서버 주소 입력
// ─────────────────────────────────────────────────────────
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _ctrl = TextEditingController();
  String _version = '';
  UpdateInfo? _availableUpdate;

  @override
  void initState() {
    super.initState();
    _load();
    _checkVersion();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _ctrl.text = p.getString('server') ?? '100.91.100.33:9001';
  }

  Future<void> _checkVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {}
    // 백그라운드로 업데이트 체크
    final upd = await Updater.checkLatest();
    if (mounted && upd != null) setState(() => _availableUpdate = upd);
  }

  Future<void> _connect() async {
    final addr = _ctrl.text.trim();
    if (addr.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('server', addr);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WindowListPage(server: addr)),
    );
  }

  Future<void> _goFileSend() async {
    final addr = _ctrl.text.trim();
    if (addr.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('server', addr);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FileSendPage(server: addr)),
    );
  }

  Future<void> _doUpdate() async {
    final upd = _availableUpdate;
    if (upd == null) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: upd),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RemoteWindow'),
        actions: [
          if (_availableUpdate != null)
            IconButton(
              icon: const Badge(
                label: Text('NEW'),
                child: Icon(Icons.system_update),
              ),
              tooltip: '업데이트 ${_availableUpdate!.version}',
              onPressed: _doUpdate,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Text('매장 PC 서버 주소', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                hintText: '100.91.100.33:9001',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.tv),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('윈도우 보기 / 제어', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _goFileSend,
              icon: const Icon(Icons.upload_file),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('파일 / 사진 보내기', style: TextStyle(fontSize: 16)),
              ),
            ),
            const Spacer(),
            const Text(
              '※ Tailscale VPN 켜져 있어야 함\n※ 같은 Tailnet 인 매장 PC 가상 IP 입력',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('v$_version',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                if (_availableUpdate != null)
                  TextButton(
                    onPressed: _doUpdate,
                    child: Text('업데이트 → v${_availableUpdate!.version}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 업데이트 다이얼로그
// ─────────────────────────────────────────────────────────
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  int _received = 0;
  int _total = 0;
  String? _error;
  bool _downloading = false;

  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await Updater.downloadAndInstall(
        widget.info,
        onProgress: (r, t) {
          if (mounted) setState(() {
            _received = r;
            _total = t;
          });
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() {
        _downloading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mb = (_total / 1024 / 1024).toStringAsFixed(1);
    final recvMb = (_received / 1024 / 1024).toStringAsFixed(1);
    final ratio = _total == 0 ? 0.0 : _received / _total;
    return AlertDialog(
      title: Text('업데이트 v${widget.info.version}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.info.body.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(widget.info.body,
                    style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 16),
            if (_downloading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: ratio),
                  const SizedBox(height: 8),
                  Text('$recvMb / $mb MB',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('나중에'),
          ),
        if (!_downloading)
          FilledButton(onPressed: _start, child: const Text('지금 설치')),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// 2) 윈도우 목록 화면
// ─────────────────────────────────────────────────────────
class WindowInfo {
  final int id;
  final String title;
  final String appName;
  final int width;
  final int height;

  WindowInfo({
    required this.id,
    required this.title,
    required this.appName,
    required this.width,
    required this.height,
  });

  factory WindowInfo.fromJson(Map<String, dynamic> j) => WindowInfo(
        id: j['id'] ?? 0,
        title: j['title'] ?? '',
        appName: j['app_name'] ?? '',
        width: j['width'] ?? 0,
        height: j['height'] ?? 0,
      );
}

class WindowListPage extends StatefulWidget {
  final String server;
  const WindowListPage({super.key, required this.server});
  @override
  State<WindowListPage> createState() => _WindowListPageState();
}

class _WindowListPageState extends State<WindowListPage> {
  WebSocketChannel? _ch;
  List<WindowInfo> _windows = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      _ch = IOWebSocketChannel.connect(Uri.parse('ws://${widget.server}/ws'));
      _ch!.stream.listen(
        _onMessage,
        onError: (e) => setState(() {
          _error = '연결 실패: $e';
          _loading = false;
        }),
        onDone: () {
          if (mounted && _windows.isEmpty) {
            setState(() {
              _error = '서버 연결 끊김';
              _loading = false;
            });
          }
        },
      );
      _ch!.sink.add(jsonEncode({'action': 'list_windows'}));
    } catch (e) {
      setState(() {
        _error = '연결 실패: $e';
        _loading = false;
      });
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      if (j['type'] == 'windows') {
        final list = (j['data'] as List)
            .map((e) => WindowInfo.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _windows = list;
          _loading = false;
        });
      } else if (j['type'] == 'error') {
        setState(() {
          _error = j['message'] as String;
          _loading = false;
        });
      }
    } catch (e) {
      // ignore parse errors
    }
  }

  void _open(WindowInfo w) {
    _ch?.sink.close();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StreamPage(server: widget.server, window: w),
      ),
    );
  }

  @override
  void dispose() {
    _ch?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('윈도우 선택'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _windows = [];
                _loading = true;
                _error = null;
              });
              _ch?.sink.close();
              _connect();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : ListView.separated(
                  itemCount: _windows.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Colors.white12),
                  itemBuilder: (_, i) {
                    final w = _windows[i];
                    return ListTile(
                      leading: const Icon(Icons.window),
                      title: Text(w.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${w.appName}  •  ${w.width}×${w.height}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(w),
                    );
                  },
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 3) 스트리밍 화면 — JPEG 프레임 표시 + 탭/롱프레스 → 입력 전송
// ─────────────────────────────────────────────────────────
class StreamPage extends StatefulWidget {
  final String server;
  final WindowInfo window;
  const StreamPage({super.key, required this.server, required this.window});
  @override
  State<StreamPage> createState() => _StreamPageState();
}

class _StreamPageState extends State<StreamPage> {
  WebSocketChannel? _ch;
  Uint8List? _frame;
  String? _error;
  final int _fps = 15;
  final int _quality = 70;
  int _frameCount = 0;
  DateTime _lastFpsTick = DateTime.now();
  double _measuredFps = 0;

  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      _ch = IOWebSocketChannel.connect(Uri.parse('ws://${widget.server}/ws'));
      _ch!.stream.listen(_onMessage, onError: (e) {
        if (mounted) setState(() => _error = '$e');
      });
      _ch!.sink.add(jsonEncode({
        'action': 'stream',
        'window_id': widget.window.id,
        'fps': _fps,
        'quality': _quality,
      }));
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      if (j['type'] == 'frame') {
        final b64 = j['jpeg_b64'] as String;
        final bytes = base64Decode(b64);
        _frameCount++;
        final now = DateTime.now();
        final elapsed = now.difference(_lastFpsTick).inMilliseconds;
        if (elapsed >= 1000) {
          _measuredFps = _frameCount * 1000 / elapsed;
          _frameCount = 0;
          _lastFpsTick = now;
        }
        setState(() {
          _frame = bytes;
        });
      } else if (j['type'] == 'error') {
        setState(() => _error = j['message'] as String);
      }
    } catch (_) {}
  }

  // 화면 좌표 → 원본 윈도우 좌표 변환
  Offset _toWindowCoords(Offset localPos) {
    final ctx = _imageKey.currentContext;
    if (ctx == null) return Offset.zero;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    final size = box.size;
    final sx = widget.window.width / size.width;
    final sy = widget.window.height / size.height;
    return Offset(localPos.dx * sx, localPos.dy * sy);
  }

  void _sendInput(Map<String, dynamic> event) {
    _ch?.sink.add(jsonEncode({
      'action': 'input',
      'window_id': widget.window.id,
      'event': event,
    }));
  }

  void _onTap(TapUpDetails d) {
    final p = _toWindowCoords(d.localPosition);
    _sendInput({
      'type': 'click',
      'x': p.dx.round(),
      'y': p.dy.round(),
      'button': 'left',
    });
  }

  void _onLongPress(LongPressStartDetails d) {
    final p = _toWindowCoords(d.localPosition);
    _sendInput({
      'type': 'longpress',
      'x': p.dx.round(),
      'y': p.dy.round(),
    });
  }

  void _onDoubleTap(TapDownDetails d) {
    final p = _toWindowCoords(d.localPosition);
    _sendInput({
      'type': 'doubleclick',
      'x': p.dx.round(),
      'y': p.dy.round(),
    });
  }

  @override
  void dispose() {
    _ch?.sink.add(jsonEncode({'action': 'stop'}));
    _ch?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.window.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Center(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('${_measuredFps.toStringAsFixed(1)} fps',
                style: const TextStyle(fontSize: 12)),
          )),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ))
          : _frame == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: GestureDetector(
                    onTapUp: _onTap,
                    onDoubleTapDown: _onDoubleTap,
                    onLongPressStart: _onLongPress,
                    child: Image.memory(
                      _frame!,
                      key: _imageKey,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 4) 파일 보내기 화면 — 사진 / 일반 파일 선택 → 청크 업로드
// ─────────────────────────────────────────────────────────
class FileSendPage extends StatefulWidget {
  final String server;
  const FileSendPage({super.key, required this.server});
  @override
  State<FileSendPage> createState() => _FileSendPageState();
}

class _UploadJob {
  final String name;
  int received;
  int total;
  String? donePath;
  String? error;
  _UploadJob({required this.name, this.received = 0, this.total = 0});
}

class _FileSendPageState extends State<FileSendPage> {
  WebSocketChannel? _ch;
  UploadController? _uploader;
  String? _connError;
  bool _connected = false;
  final List<_UploadJob> _jobs = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      _ch = IOWebSocketChannel.connect(Uri.parse('ws://${widget.server}/ws'));
      _uploader = UploadController(_ch!);
      _uploader!.progress.listen((p) {
        if (_jobs.isEmpty) return;
        final job = _jobs.last;
        if (p.error != null) {
          job.error = p.error;
        } else {
          job.received = p.received;
          job.total = p.total;
          if (p.donePath != null) job.donePath = p.donePath;
        }
        if (mounted) setState(() {});
      });
      _ch!.stream.listen((raw) {
        try {
          final j = jsonDecode(raw as String) as Map<String, dynamic>;
          _uploader?.handleMessage(j);
        } catch (_) {}
      }, onError: (e) {
        if (mounted) setState(() => _connError = '$e');
      }, onDone: () {
        if (mounted) setState(() => _connected = false);
      });
      if (mounted) setState(() => _connected = true);
    } catch (e) {
      if (mounted) setState(() => _connError = '$e');
    }
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final list = await picker.pickMultiImage(imageQuality: 100);
    if (list.isEmpty) return;
    for (final x in list) {
      await _sendOne(File(x.path), x.name);
    }
  }

  Future<void> _pickCamera() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 100);
    if (x == null) return;
    await _sendOne(File(x.path), x.name);
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (res == null) return;
    for (final f in res.files) {
      final path = f.path;
      if (path == null) continue;
      await _sendOne(File(path), f.name);
    }
  }

  Future<void> _sendOne(File file, String name) async {
    if (_uploader == null || !_connected) return;
    setState(() {
      _busy = true;
      _jobs.add(_UploadJob(name: name));
    });
    try {
      await _uploader!.send(file);
    } catch (e) {
      if (mounted) {
        setState(() {
          _jobs.last.error = '$e';
        });
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _uploader?.dispose();
    _ch?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('파일 보내기'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                _connected ? '연결됨' : '연결 안됨',
                style: TextStyle(
                  fontSize: 12,
                  color: _connected ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_connError != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.red.withValues(alpha: 0.2),
                width: double.infinity,
                child: Text('연결 오류: $_connError',
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pickPhotos,
                    icon: const Icon(Icons.photo_library),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('갤러리'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pickCamera,
                    icon: const Icon(Icons.photo_camera),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('카메라'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickFiles,
                icon: const Icon(Icons.folder_open),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('파일 선택'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('전송 내역',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _jobs.isEmpty
                  ? const Center(
                      child: Text('아직 보낸 파일 없음',
                          style: TextStyle(color: Colors.white38)),
                    )
                  : ListView.separated(
                      itemCount: _jobs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Colors.white12),
                      itemBuilder: (_, i) {
                        final j = _jobs[_jobs.length - 1 - i];
                        return _JobTile(job: j);
                      },
                    ),
            ),
            const SizedBox(height: 8),
            const Text(
              '저장 위치: F:\\resellonjigu\\모바일전송\\YYYY-MM-DD\\',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  final _UploadJob job;
  const _JobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    final mb = (job.total / 1024 / 1024).toStringAsFixed(1);
    final recvMb = (job.received / 1024 / 1024).toStringAsFixed(1);
    final ratio = job.total == 0 ? 0.0 : job.received / job.total;
    Widget trailing;
    if (job.error != null) {
      trailing = const Icon(Icons.error, color: Colors.redAccent);
    } else if (job.donePath != null) {
      trailing = const Icon(Icons.check_circle, color: Colors.greenAccent);
    } else {
      trailing = SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${(ratio * 100).toInt()}%',
                style: const TextStyle(fontSize: 11)),
            LinearProgressIndicator(value: ratio),
          ],
        ),
      );
    }
    return ListTile(
      dense: true,
      leading: const Icon(Icons.file_present, size: 20),
      title: Text(job.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        job.error != null
            ? job.error!
            : job.donePath != null
                ? '완료: $mb MB'
                : '$recvMb / $mb MB',
        style: TextStyle(
          fontSize: 11,
          color: job.error != null ? Colors.redAccent : Colors.white60,
        ),
      ),
      trailing: trailing,
    );
  }
}
