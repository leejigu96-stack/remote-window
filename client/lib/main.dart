// RemoteWindow Client — 매장 PC 특정 윈도우 실시간 모니터링/제어
// Sprint 2 PoC: 서버 주소 입력 → 윈도우 목록 → 스트리밍 + 탭 = 클릭

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import 'tailscale.dart';
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

// pubspec.yaml 의 version 과 동기화 (PackageInfo 실패 시 fallback)
const String kAppVersionFallback = '0.1.19';

class _ConnectPageState extends State<ConnectPage> {
  final _ctrl = TextEditingController();
  String _version = kAppVersionFallback;
  UpdateInfo? _availableUpdate;
  bool _tailscaleInstalled = true; // 초기엔 가정만 — 체크 후 갱신

  @override
  void initState() {
    super.initState();
    _load();
    _checkVersion();
    _checkTailscale();
  }

  Future<void> _checkTailscale() async {
    final ok = await Tailscale.isInstalled();
    if (!mounted) return;
    setState(() => _tailscaleInstalled = ok);
    if (!ok) {
      // 첫 진입 시 자동으로 안내 다이얼로그
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTailscaleInstallDialog();
      });
    }
  }

  void _showTailscaleInstallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Tailscale 설치 필요'),
        content: const Text(
          'RemoteWindow 는 Tailscale VPN 으로 매장 PC에 연결합니다.\n\n'
          'Tailscale 앱을 먼저 설치하고, 매장 PC 와 같은 구글 계정으로 로그인해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('나중에'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await Tailscale.openPlayStore();
            },
            icon: const Icon(Icons.shop),
            label: const Text('Play Store 에서 설치'),
          ),
        ],
      ),
    );
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
    // 시작 시 이전 APK 잔여물 청소 (이전 업데이트들에서 남은 파일)
    Updater.cleanupOldApks();
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
        title: Row(
          children: [
            const Text('RemoteWindow'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('v$_version',
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
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
            const SizedBox(height: 16),
            // ★ VPN 없이 상품 DB 보기 (구글드라이브 경유) — 주력 기능
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1b9e77),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DbViewPage()),
              ),
              icon: const Icon(Icons.storefront),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('상품 DB 보기  ·  VPN 없이',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 6),
            const Text('인터넷만 있으면 됨 · VPN 불필요',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 18),
            const Divider(color: Colors.white24),
            const SizedBox(height: 10),
            const Text('— 아래는 실시간 화면 보기/제어 (Tailscale 필요) —',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 14),
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
            const SizedBox(height: 12),
            if (!_tailscaleInstalled)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange, size: 18),
                        SizedBox(width: 6),
                        Text('Tailscale 앱이 설치되지 않음',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tailscale VPN 없이는 매장 PC 와 연결할 수 없습니다.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: Tailscale.openPlayStore,
                      icon: const Icon(Icons.shop),
                      label: const Text('Play Store 에서 설치'),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 6),
                  const Text('Tailscale 설치됨',
                      style: TextStyle(
                          fontSize: 12, color: Colors.greenAccent)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: Tailscale.launch,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Tailscale 열기'),
                  ),
                ],
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
// 연결 에러 안내 위젯 (윈도우 목록 / 파일 보내기 공용)
// ─────────────────────────────────────────────────────────
class _ConnectionErrorView extends StatelessWidget {
  final String server;
  final String error;
  final VoidCallback onRetry;
  const _ConnectionErrorView({
    required this.server,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.signal_wifi_connected_no_internet_4,
              color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          const Text('서버 연결 실패',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('주소: $server',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 4),
          Text(error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          const SizedBox(height: 24),
          const Text('확인할 것:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _checklistItem('① Tailscale VPN 켜져 있나요?',
              '폰 Tailscale 앱에서 토글 ON 인지 확인. 매장 PC 가 같은 Tailnet 에 보여야 함.'),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: () async {
              final ok = await Tailscale.launch();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Tailscale 앱을 열 수 없어요')),
                );
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Tailscale 앱 열기'),
          ),
          const SizedBox(height: 16),
          _checklistItem('② 매장 PC 가 켜져 있고 서버 실행 중인가요?',
              '매장 PC 에서 F:\\remote-window\\server\\run-server.bat 더블클릭 후 "WebSocket listening on 0.0.0.0:9001" 메시지가 떠야 함.'),
          const SizedBox(height: 16),
          _checklistItem('③ 서버 주소가 맞나요?',
              'Tailscale 앱에서 매장 PC 의 IP 를 확인 후 100.X.X.X:9001 형식으로 입력했나 확인.'),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('다시 시도'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('이전으로 (주소 변경)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checklistItem(String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(desc,
              style: const TextStyle(
                  fontSize: 11, color: Colors.white70)),
        ],
      ),
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
  Set<String> _favorites = {}; // 사용자가 즐겨찾기로 추가한 윈도우 키
  String? _error;
  bool _loading = true;
  bool _showAll = false; // 토글: 즐겨찾기 안에 안 든 거까지 모두 표시

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _connect();
  }

  Future<void> _loadFavorites() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('favorite_windows') ?? [];
    if (mounted) setState(() => _favorites = list.toSet());
    // 즐겨찾기 비어있으면 처음엔 자동으로 전체 표시 (선택할 수 있게)
    if (_favorites.isEmpty) {
      setState(() => _showAll = true);
    }
  }

  Future<void> _saveFavorites() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('favorite_windows', _favorites.toList());
  }

  String _keyFor(WindowInfo w) {
    // 앱 이름 + 제목 패턴 (같은 앱의 다른 창 구분 위해)
    return '${w.appName}|${w.title}';
  }

  Future<void> _toggleFavorite(WindowInfo w) async {
    final key = _keyFor(w);
    setState(() {
      if (_favorites.contains(key)) {
        _favorites.remove(key);
      } else {
        _favorites.add(key);
      }
    });
    await _saveFavorites();
  }

  Future<void> _clearFavorites() async {
    setState(() => _favorites.clear());
    await _saveFavorites();
  }

  List<WindowInfo> get _filtered {
    if (_showAll) return _windows;
    return _windows.where((w) => _favorites.contains(_keyFor(w))).toList();
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
    // WS 는 살려둠 — 뒤로 오면 목록 그대로 (재연결 안 함)
    Navigator.push(
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
        title: Text(_showAll
            ? '전체 윈도우 (★ 표시로 즐겨찾기 추가)'
            : '즐겨찾기 ${_favorites.length}'),
        actions: [
          IconButton(
            tooltip: _showAll ? '즐겨찾기만 보기' : '전체 보기',
            icon: Icon(_showAll ? Icons.star : Icons.apps),
            onPressed: () => setState(() => _showAll = !_showAll),
          ),
          IconButton(
            tooltip: '새로고침',
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
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') _clearFavorites();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'reset',
                child: Text('즐겨찾기 비우기'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ConnectionErrorView(
                  server: widget.server,
                  error: _error!,
                  onRetry: () {
                    setState(() {
                      _windows = [];
                      _loading = true;
                      _error = null;
                    });
                    _ch?.sink.close();
                    _connect();
                  },
                )
              : _filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_border,
                                size: 48, color: Colors.white38),
                            const SizedBox(height: 12),
                            const Text('즐겨찾기에 추가된 윈도우 없음',
                                style: TextStyle(fontSize: 16)),
                            const SizedBox(height: 8),
                            const Text(
                              '우상단 ▦ 아이콘 → 전체 윈도우 → ★ 로 추가',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () =>
                                  setState(() => _showAll = true),
                              icon: const Icon(Icons.apps),
                              label: const Text('전체 윈도우 보기'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Colors.white12),
                      itemBuilder: (_, i) {
                        final w = _filtered[i];
                        final isFav = _favorites.contains(_keyFor(w));
                        return ListTile(
                          leading: Icon(
                            isFav ? Icons.star : Icons.window,
                            color: isFav ? Colors.amber : Colors.white54,
                          ),
                          title: Text(w.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${w.appName}  •  ${w.width}×${w.height}'),
                          trailing: IconButton(
                            icon: Icon(
                              isFav ? Icons.star : Icons.star_border,
                              color: isFav ? Colors.amber : null,
                              size: 22,
                            ),
                            tooltip: isFav ? '즐겨찾기 해제' : '즐겨찾기에 추가',
                            onPressed: () => _toggleFavorite(w),
                          ),
                          onTap: () => _open(w),
                          onLongPress: () => _toggleFavorite(w),
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

  // 줌/팬 — 직접 관리 (IV 제거)
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _baseOffset = Offset.zero;

  // 디버그 카운터 (v0.1.12) — 어떤 핸들러가 firing 되는지 화면에서 확인용
  int _dbgScaleStart = 0;
  int _dbgScaleUpdate = 0;
  int _dbgScrollSent = 0;
  int _dbgPointers = 0;
  bool _showDebug = false;

  // 2-손가락 스크롤 누적 (IV onInteractionUpdate 콜백)
  double _scrollAccum = 0;
  DateTime _lastScrollSent = DateTime.now();

  // 키보드 (Google RD 방식) — 숨김 TextField + zero-width space padding
  static const String _kbPad = '​';
  final TextEditingController _kbCtrl = TextEditingController(text: _kbPad);
  final FocusNode _kbFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _kbCtrl.addListener(_onKeyboardInput);
    _kbFocus.addListener(_onKbFocusChange);
    _connect();
  }

  void _onKeyboardInput() {
    final v = _kbCtrl.value;
    // IME 조합 중이면 대기 (한글 입력 등)
    if (v.composing.isValid && !v.composing.isCollapsed) return;
    final t = v.text;
    if (t == _kbPad) return; // 초기 상태
    if (t.isEmpty) {
      // 백스페이스 (padding 까지 삭제됨)
      _sendCombo(['backspace']);
    } else if (t.startsWith(_kbPad)) {
      // 새 문자 입력됨 (padding 뒤에 붙음)
      final added = t.substring(1);
      _sendKey(added);
    } else {
      // padding 사라진 비정상 케이스 — 그냥 보냄
      _sendKey(t);
    }
    // 다음 입력 받기 위해 padding 복원
    _kbCtrl.value = const TextEditingValue(
      text: _kbPad,
      selection: TextSelection.collapsed(offset: 1),
    );
  }

  void _toggleKeyboard() {
    if (_kbFocus.hasFocus) {
      _kbFocus.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } else {
      FocusScope.of(context).requestFocus(_kbFocus);
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  void _onKbFocusChange() {
    if (!_kbFocus.hasFocus) {
      // 안전망 — 어떤 경로로든 포커스 잃으면 IME 도 명시적으로 닫기
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
    if (mounted) setState(() {}); // PopScope.canPop 재평가 + 시각 표시 업데이트
  }

  /// 화면 중앙 좌표로 스크롤 이벤트 전송
  void _sendScrollAtCenter(double dy) {
    final ctx = _imageKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final center = Offset(box.size.width / 2, box.size.height / 2);
    final p = _toWindowCoords(center);
    final delta = (-dy * 6).round();
    _sendInput({
      'type': 'scroll',
      'x': p.dx.round(),
      'y': p.dy.round(),
      'delta_x': 0,
      'delta_y': delta,
    });
  }

  void _scrollButton(int dyWheel) {
    final ctx = _imageKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final center = Offset(box.size.width / 2, box.size.height / 2);
    final p = _toWindowCoords(center);
    _sendInput({
      'type': 'scroll',
      'x': p.dx.round(),
      'y': p.dy.round(),
      'delta_x': 0,
      'delta_y': dyWheel,
    });
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
      // 바이너리 프레임 (v0.1.5 이후)
      if (raw is Uint8List || raw is List<int>) {
        final bytes =
            raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
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
        return;
      }
      // 텍스트 JSON 메시지 (에러 등)
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      if (j['type'] == 'error') {
        setState(() => _error = j['message'] as String);
      }
    } catch (_) {}
  }

  // 화면 좌표 → 원본 윈도우 좌표 변환
  // GestureDetector 는 Image 직속 자식 → localPosition 이 이미 이미지 좌표
  // (InteractiveViewer 가 외곽에서 transform 처리해줌)
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

  void _sendKey(String text) {
    if (text.isEmpty) return;
    _sendInput({'type': 'key', 'text': text});
  }

  void _sendCombo(List<String> keys) {
    _sendInput({'type': 'keycombo', 'keys': keys});
  }

  /// 특수키 패널 (별도 호출)
  Future<void> _showSpecialKeysSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1D22),
      builder: (ctx) {
        Widget chip(String label, List<String> keys) => ActionChip(
              label: Text(label),
              onPressed: () => _sendCombo(keys),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('특수키',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  chip('Enter', ['enter']),
                  chip('Tab', ['tab']),
                  chip('Esc', ['escape']),
                  chip('Backspace', ['backspace']),
                  chip('Delete', ['delete']),
                  chip('Space', ['space']),
                ]),
                const SizedBox(height: 12),
                const Text('방향키',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  chip('←', ['left']),
                  chip('→', ['right']),
                  chip('↑', ['up']),
                  chip('↓', ['down']),
                  chip('Home', ['home']),
                  chip('End', ['end']),
                  chip('PgUp', ['pageup']),
                  chip('PgDn', ['pagedown']),
                ]),
                const SizedBox(height: 12),
                const Text('단축키',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  chip('Ctrl+C 복사', ['ctrl', 'c']),
                  chip('Ctrl+V 붙여넣기', ['ctrl', 'v']),
                  chip('Ctrl+X 잘라내기', ['ctrl', 'x']),
                  chip('Ctrl+A 전체선택', ['ctrl', 'a']),
                  chip('Ctrl+Z 실행취소', ['ctrl', 'z']),
                  chip('Ctrl+Y 재실행', ['ctrl', 'y']),
                  chip('Ctrl+S 저장', ['ctrl', 's']),
                  chip('Ctrl+F 찾기', ['ctrl', 'f']),
                  chip('Alt+Tab', ['alt', 'tab']),
                  chip('Win+D 바탕화면', ['win', 'd']),
                ]),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _kbCtrl.removeListener(_onKeyboardInput);
    _kbFocus.removeListener(_onKbFocusChange);
    _kbCtrl.dispose();
    _kbFocus.dispose();
    _ch?.sink.add(jsonEncode({'action': 'stop'}));
    _ch?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 키보드 떠있으면 뒤로가기 1번 = 키보드 닫기 (페이지는 그대로)
      canPop: !_kbFocus.hasFocus,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _kbFocus.hasFocus) {
          _kbFocus.unfocus();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.window.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _kbFocus.hasFocus ? '키보드 끄기' : '키보드 입력',
            icon: Icon(
              _kbFocus.hasFocus ? Icons.keyboard_hide : Icons.keyboard,
              color: _kbFocus.hasFocus ? Colors.greenAccent : null,
            ),
            onPressed: _toggleKeyboard,
          ),
          IconButton(
            tooltip: '특수키 / 단축키',
            icon: const Icon(Icons.keyboard_command_key),
            onPressed: _showSpecialKeysSheet,
          ),
          IconButton(
            tooltip: _showDebug ? '디버그 끄기' : '디버그 켜기 (제스처 카운터)',
            icon: Icon(_showDebug ? Icons.bug_report : Icons.bug_report_outlined,
                color: _showDebug ? Colors.amber : null),
            onPressed: () => setState(() => _showDebug = !_showDebug),
          ),
          Center(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('${_measuredFps.toStringAsFixed(1)} fps',
                style: const TextStyle(fontSize: 11)),
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
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    // 비주얼 — Transform 으로 줌/팬
                    Center(
                      child: Transform(
                        transform: Matrix4.identity()
                          ..translate(_offset.dx, _offset.dy)
                          ..scale(_scale),
                        alignment: Alignment.center,
                        child: Image.memory(
                          _frame!,
                          key: _imageKey,
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    // 단일 RawGestureDetector — 모든 제스처 명시적 등록
                    Positioned.fill(
                      child: Listener(
                        // Listener 로 pointer 개수만 추적 (디버그용 + scroll-end 안전망)
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (e) {
                          _dbgPointers++;
                          if (_showDebug && mounted) setState(() {});
                        },
                        onPointerUp: (e) {
                          if (_dbgPointers > 0) _dbgPointers--;
                          if (_showDebug && mounted) setState(() {});
                        },
                        onPointerCancel: (e) {
                          if (_dbgPointers > 0) _dbgPointers--;
                          if (_showDebug && mounted) setState(() {});
                        },
                        child: RawGestureDetector(
                          behavior: HitTestBehavior.opaque,
                          gestures: <Type, GestureRecognizerFactory>{
                            TapGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                    TapGestureRecognizer>(
                              () => TapGestureRecognizer(),
                              (TapGestureRecognizer i) {
                                i.onTapUp = _onTap;
                              },
                            ),
                            DoubleTapGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                    DoubleTapGestureRecognizer>(
                              () => DoubleTapGestureRecognizer(),
                              (DoubleTapGestureRecognizer i) {
                                i.onDoubleTapDown = _onDoubleTap;
                              },
                            ),
                            LongPressGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                    LongPressGestureRecognizer>(
                              () => LongPressGestureRecognizer(),
                              (LongPressGestureRecognizer i) {
                                i.onLongPressStart = _onLongPress;
                              },
                            ),
                            ScaleGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                    ScaleGestureRecognizer>(
                              () => ScaleGestureRecognizer(),
                              (ScaleGestureRecognizer i) {
                                i.onStart = (d) {
                                  _dbgScaleStart++;
                                  _baseScale = _scale;
                                  _baseOffset = _offset;
                                  _scrollAccum = 0;
                                  if (_showDebug && mounted) setState(() {});
                                };
                                i.onUpdate = (d) {
                                  _dbgScaleUpdate++;
                                  if (d.pointerCount < 2) {
                                    if (_showDebug && mounted) setState(() {});
                                    return;
                                  }
                                  if ((d.scale - 1.0).abs() > 0.02) {
                                    // 핀치 → 로컬 줌
                                    setState(() {
                                      _scale = (_baseScale * d.scale)
                                          .clamp(1.0, 5.0);
                                      if (_scale < 1.001) {
                                        _offset = Offset.zero;
                                      }
                                    });
                                  } else {
                                    if (_scale < 1.05) {
                                      // 줌 아닐 때 → PC 스크롤
                                      _scrollAccum += d.focalPointDelta.dy;
                                      final now = DateTime.now();
                                      if (now
                                                  .difference(_lastScrollSent)
                                                  .inMilliseconds >=
                                              30 &&
                                          _scrollAccum.abs() >= 2) {
                                        _sendScrollAtCenter(_scrollAccum);
                                        _dbgScrollSent++;
                                        _scrollAccum = 0;
                                        _lastScrollSent = now;
                                      }
                                    } else {
                                      // 줌 상태 → 로컬 팬
                                      setState(() {
                                        _offset += d.focalPointDelta;
                                      });
                                    }
                                  }
                                  if (_showDebug && mounted) setState(() {});
                                };
                                i.onEnd = (_) {
                                  _scrollAccum = 0;
                                };
                              },
                            ),
                          },
                        ),
                      ),
                    ),
                    // 디버그 오버레이
                    if (_showDebug)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          color: Colors.black.withValues(alpha: 0.7),
                          child: Text(
                            'pts:$_dbgPointers  '
                            'scale start:$_dbgScaleStart upd:$_dbgScaleUpdate  '
                            'scroll:$_dbgScrollSent  '
                            'kb:${_kbFocus.hasFocus ? "ON" : "off"}',
                            style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 10,
                                fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    // 우측 가장자리 스크롤 보조 버튼
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _scrollFab(Icons.keyboard_arrow_up,
                                () => _scrollButton(120)),
                            const SizedBox(height: 8),
                            _scrollFab(Icons.keyboard_arrow_down,
                                () => _scrollButton(-120)),
                          ],
                        ),
                      ),
                    ),
                    // 숨김 TextField — 키보드 입력 받기 (Google RD 방식)
                    Positioned(
                      left: 0,
                      top: -100,
                      child: SizedBox(
                        width: 1,
                        height: 1,
                        child: TextField(
                          controller: _kbCtrl,
                          focusNode: _kbFocus,
                          autocorrect: false,
                          enableSuggestions: false,
                          showCursor: false,
                          maxLines: 1,
                          textInputAction: TextInputAction.send,
                          // Enter 누르면 onSubmitted 발화 → PC 에 엔터 전송
                          // (포커스 유지해서 키보드 계속 열린 채로 다음 입력 받기)
                          onSubmitted: (_) {
                            _sendCombo(['enter']);
                            FocusScope.of(context).requestFocus(_kbFocus);
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(color: Colors.transparent),
                        ),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _scrollFab(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 24),
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
  final int index; // ★보낸 순번(1부터) — 카톡처럼 순서 표시
  final String name;
  final String? path; // ★로컬 경로 — 이미지 썸네일 미리보기용
  final bool isImage;
  int received;
  int total;
  String? donePath;
  String? error;
  _UploadJob({
    required this.index,
    required this.name,
    this.path,
    this.isImage = false,
    this.received = 0,
    this.total = 0,
  });
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
        // ★순차 업로드라 '아직 안 끝난 첫 job'이 현재 전송 중인 파일 (last 고정 버그 수정 — 진행률이 엉뚱한 줄에 찍히던 것)
        final job = _jobs.firstWhere(
          (j) => j.donePath == null && j.error == null,
          orElse: () => _jobs.last,
        );
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
    // ★카톡식 커스텀 갤러리 — 선택 순서대로 1·2·3 번호가 뜨고, 그 순서대로 전송
    final selected = await Navigator.push<List<AssetEntity>>(
      context,
      MaterialPageRoute(builder: (_) => const GalleryPickerPage()),
    );
    if (selected == null || selected.isEmpty) return;
    for (final a in selected) {
      final f = await a.file;
      if (f != null) {
        await _sendOne(f, a.title ?? '${a.id}.jpg');
      }
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
    final isImg = RegExp(r'\.(jpe?g|png|gif|webp|heic|bmp)$', caseSensitive: false)
        .hasMatch(name);
    setState(() {
      _busy = true;
      _jobs.add(_UploadJob(
        index: _jobs.length + 1,
        name: name,
        path: file.path,
        isImage: isImg,
      ));
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
                        // ★보낸 순서대로(1번째가 맨 위) — 카톡처럼 순서 확인용
                        final j = _jobs[i];
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
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ★순번 배지 (카톡처럼 보낸 순서 1·2·3…)
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF6C5CE7),
              shape: BoxShape.circle,
            ),
            child: Text('${job.index}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
          const SizedBox(width: 8),
          // ★이미지면 썸네일 미리보기, 아니면 파일 아이콘
          (job.isImage && job.path != null)
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    File(job.path!),
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.image, size: 20),
                  ),
                )
              : const Icon(Icons.file_present, size: 20),
        ],
      ),
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

// ─────────────────────────────────────────────────────────
// 4-1) 카톡식 커스텀 갤러리 — 탭하면 선택 순서대로 1·2·3 번호, 그 순서로 전송
// ─────────────────────────────────────────────────────────
class GalleryPickerPage extends StatefulWidget {
  const GalleryPickerPage({super.key});
  @override
  State<GalleryPickerPage> createState() => _GalleryPickerPageState();
}

class _GalleryPickerPageState extends State<GalleryPickerPage> {
  final List<AssetEntity> _photos = [];
  final List<AssetEntity> _selected = []; // ★선택 순서 유지 (인덱스 = 보낼 순번)
  bool _loading = true;
  String? _error;
  AssetPathEntity? _album;
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '사진 접근 권한이 필요해요. 설정 → RemoteWindow → 권한 → 사진 허용';
        });
      }
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image, onlyAll: true);
    if (albums.isEmpty) {
      if (mounted) setState(() { _loading = false; _error = '사진이 없어요'; });
      return;
    }
    _album = albums.first;
    await _loadMore();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_album == null || !_hasMore || _loadingMore) return;
    _loadingMore = true;
    final batch = await _album!.getAssetListPaged(page: _page, size: 60);
    if (batch.isEmpty) {
      _hasMore = false;
    } else {
      _photos.addAll(batch);
      _page++;
      if (mounted) setState(() {});
    }
    _loadingMore = false;
  }

  void _toggle(AssetEntity a) {
    setState(() {
      if (_selected.contains(a)) {
        _selected.remove(a);
      } else {
        _selected.add(a);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? '사진 선택' : '사진 선택 ${_selected.length}장'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected),
            child: Text(
              _selected.isEmpty ? '전송' : '전송 ${_selected.length}',
              style: TextStyle(
                color: _selected.isEmpty ? Colors.white38 : Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(2),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: _photos.length,
                    itemBuilder: (_, i) {
                      final a = _photos[i];
                      final idx = _selected.indexOf(a);
                      final sel = idx >= 0;
                      return GestureDetector(
                        onTap: () => _toggle(a),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FutureBuilder<Uint8List?>(
                              future: a.thumbnailDataWithSize(
                                  const ThumbnailSize.square(200)),
                              builder: (_, snap) => snap.data == null
                                  ? Container(color: Colors.white10)
                                  : Image.memory(snap.data!,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true),
                            ),
                            if (sel)
                              Container(
                                  color: Colors.black.withValues(alpha: 0.35)),
                            // ★선택 순서 번호 배지 (카톡식)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: sel
                                      ? const Color(0xFF6C5CE7)
                                      : Colors.black26,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: sel
                                    ? Text('${idx + 1}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold))
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 5) 상품 DB 보기 — 리셀온 프로그램의 그 대시보드(dashboard.html)를 그대로 표시
//    ★프로그램 '상품 DB' = unified_db/dashboard.html. PC가 드라이브에 올린 그 파일을
//    받아 WebView 로 렌더 → 프로그램과 똑같은 화면(모바일 반응형 카드). VPN 불필요.
// ─────────────────────────────────────────────────────────
class DbViewPage extends StatefulWidget {
  const DbViewPage({super.key});
  @override
  State<DbViewPage> createState() => _DbViewPageState();
}

class _DbViewPageState extends State<DbViewPage> {
  static const String _dbUrl =
      'https://drive.google.com/uc?export=download&id=1kgqy_ly9R7RwTBbaKUMSpr8J-hdIo_R0';

  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFededea));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await http.get(
        Uri.parse(_dbUrl),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 40));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ' + resp.statusCode.toString());
      }
      final html = utf8.decode(resp.bodyBytes);
      if (!html.toLowerCase().contains('<html') && !html.contains('mcards')) {
        throw Exception('DB 형식 오류 (' + html.length.toString() + ')');
      }
      await _controller.loadHtmlString(html);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 뒤로가기 = WebView 안에서 한 단계 뒤로(상품링크/모달). 더 못 가면 그때 홈으로.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          _controller.goBack();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('상품 DB'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            Container(
              color: const Color(0xFFededea),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('상품 DB 불러오는 중…',
                        style: TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Container(
              color: const Color(0xFF101216),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off,
                          color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      const Text('DB 를 불러오지 못했어요',
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(_error ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('다시 시도'),
                      ),
                    ],
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

