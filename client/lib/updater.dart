// 셀프 업데이트 — GitHub Releases 에서 최신 버전 체크 + APK 다운로드 + 설치
//
// release 노트에 APK 한 개 (`app-release.apk` 또는 `RemoteWindow-vX.Y.Z.apk`) 첨부 가정.
// 버전은 release 태그명 (예: v0.1.1) 에서 추출.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const String repoOwner = 'leejigu96-stack';
const String repoName = 'remote-window';

class UpdateInfo {
  final String tag;          // v0.1.1
  final String version;      // 0.1.1
  final String name;         // release 제목
  final String body;         // release 본문 (changelog)
  final String apkUrl;       // APK 다운로드 URL
  final int apkSize;         // 바이트
  UpdateInfo({
    required this.tag,
    required this.version,
    required this.name,
    required this.body,
    required this.apkUrl,
    required this.apkSize,
  });
}

class Updater {
  /// 앱 임시 폴더에서 이전에 다운받은 APK 파일 모두 삭제.
  /// - 앱 시작 시 호출 → 잔여 파일 청소
  /// - 새 APK 다운로드 직전에도 호출
  static Future<void> cleanupOldApks() async {
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 새 버전 있으면 UpdateInfo, 없으면 null
  static Future<UpdateInfo?> checkLatest() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // "0.1.0"

      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String?) ?? '';
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      if (version.isEmpty) return null;

      if (!_isNewer(version, current)) return null;

      final assets = (j['assets'] as List?) ?? [];
      // .apk 첨부 파일 찾기
      Map<String, dynamic>? apk;
      for (final a in assets) {
        final m = a as Map<String, dynamic>;
        final name = (m['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apk = m;
          break;
        }
      }
      if (apk == null) return null;

      return UpdateInfo(
        tag: tag,
        version: version,
        name: (j['name'] as String?) ?? tag,
        body: (j['body'] as String?) ?? '',
        apkUrl: apk['browser_download_url'] as String,
        apkSize: (apk['size'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// "0.1.1" > "0.1.0" → true
  static bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (l.length < 3) l.add(0);
    while (c.length < 3) c.add(0);
    for (int i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  /// APK 다운로드 + 설치 인텐트 실행. 진행률은 콜백
  static Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    // 설치 권한 요청
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        throw Exception('"출처를 알 수 없는 앱 설치" 권한이 필요합니다');
      }
    }

    final dir = await getTemporaryDirectory();
    // 이전에 받아둔 APK 파일 전부 정리 (같은 이름이든 다른 버전이든)
    await cleanupOldApks();
    final file = File('${dir.path}/RemoteWindow-${info.version}.apk');
    if (await file.exists()) await file.delete();

    final req = http.Request('GET', Uri.parse(info.apkUrl));
    final resp = await req.send();
    if (resp.statusCode != 200) {
      throw Exception('다운로드 실패: HTTP ${resp.statusCode}');
    }
    final total = resp.contentLength ?? info.apkSize;
    int received = 0;

    final sink = file.openWrite();
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.flush();
    await sink.close();

    // 인텐트로 APK 설치 실행
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception('설치 실행 실패: ${result.message}');
    }
  }
}
