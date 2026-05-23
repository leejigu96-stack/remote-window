// 파일 업로드 — WebSocket 청크 방식
// 사용: UploadController.send(file)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';

class UploadProgress {
  final int received;
  final int total;
  final String? donePath;
  final String? error;
  const UploadProgress({
    required this.received,
    required this.total,
    this.donePath,
    this.error,
  });
  double get ratio => total == 0 ? 0 : received / total;
  bool get isDone => donePath != null;
}

class UploadController {
  final WebSocketChannel ch;
  final StreamController<UploadProgress> _progress = StreamController.broadcast();
  int? _activeUploadId;
  int _activeSize = 0;

  UploadController(this.ch);

  Stream<UploadProgress> get progress => _progress.stream;

  // 외부에서 ws 메시지 받았을 때 호출
  void handleMessage(Map<String, dynamic> j) {
    final t = j['type'];
    if (t == 'upload_ack') {
      _activeUploadId = (j['upload_id'] as num).toInt();
    } else if (t == 'upload_progress') {
      _progress.add(UploadProgress(
        received: (j['received'] as num).toInt(),
        total: (j['total'] as num).toInt(),
      ));
    } else if (t == 'upload_done') {
      _progress.add(UploadProgress(
        received: _activeSize,
        total: _activeSize,
        donePath: j['path'] as String?,
      ));
      _activeUploadId = null;
    } else if (t == 'error') {
      _progress.add(UploadProgress(
        received: 0,
        total: _activeSize,
        error: j['message'] as String? ?? 'unknown error',
      ));
    }
  }

  /// 파일 하나 업로드 — 청크 1MB
  Future<void> send(File file) async {
    final size = await file.length();
    _activeSize = size;
    final name = file.path.split(RegExp(r'[\\/]')).last;

    // 1) upload_start
    ch.sink.add(jsonEncode({
      'action': 'upload_start',
      'name': name,
      'size': size,
    }));

    // upload_ack 대기 (최대 5초)
    final ackTimer = Stopwatch()..start();
    while (_activeUploadId == null && ackTimer.elapsedMilliseconds < 5000) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (_activeUploadId == null) {
      _progress.add(UploadProgress(
        received: 0,
        total: size,
        error: '서버 응답 없음 (upload_ack)',
      ));
      return;
    }

    // 2) 청크 전송 (1MB)
    const chunkSize = 1024 * 1024;
    final stream = file.openRead();
    final buf = <int>[];
    int seq = 0;

    await for (final part in stream) {
      buf.addAll(part);
      while (buf.length >= chunkSize) {
        final chunk = buf.sublist(0, chunkSize);
        buf.removeRange(0, chunkSize);
        ch.sink.add(jsonEncode({
          'action': 'upload_chunk',
          'upload_id': _activeUploadId,
          'seq': seq++,
          'data_b64': base64Encode(chunk),
        }));
        // 백프레셔 — 짧게 양보
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }
    if (buf.isNotEmpty) {
      ch.sink.add(jsonEncode({
        'action': 'upload_chunk',
        'upload_id': _activeUploadId,
        'seq': seq++,
        'data_b64': base64Encode(buf),
      }));
    }

    // 3) upload_end
    ch.sink.add(jsonEncode({
      'action': 'upload_end',
      'upload_id': _activeUploadId,
    }));
  }

  void dispose() {
    _progress.close();
  }
}
