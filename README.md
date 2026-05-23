# RemoteWindow

매장 PC 의 **특정 윈도우만** 모바일에서 실시간으로 보고 제어하는 PoC.

## 구조

```
F:\remote-window\
├── server\          ← 매장 PC 측 Rust 서버
│   ├── src\
│   │   ├── main.rs           서버 진입점 (0.0.0.0:9001)
│   │   ├── ws.rs             WebSocket 라우터
│   │   ├── windows_list.rs   xcap → 가시 윈도우 목록
│   │   ├── capture.rs        xcap → 단일 윈도우 JPEG 캡처
│   │   └── inject.rs         SendInput → 마우스 클릭 inject
│   ├── Cargo.toml
│   └── run-server.bat        매장 PC 에서 더블클릭으로 실행
└── client\          ← Flutter 클라이언트 (Android APK)
    ├── lib\main.dart         3개 화면: 연결 → 윈도우 목록 → 스트림
    └── android\
```

## 빌드 환경 (셋업 완료 2026-05-23)
- Rust toolchain: `D:\resellon_dev\` (cargo + rustup, CARGO_TARGET_DIR=`D:\remote-window_build_target`)
- Flutter 3.44.0 stable: `D:\flutter\`
- JDK 17 (Microsoft OpenJDK): `C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot\`
- Android SDK 36 + build-tools 36: `D:\android-sdk\`

## 프로토콜 (WebSocket JSON)

클라 → 서버:
```json
{"action": "list_windows"}
{"action": "stream", "window_id": 12345, "fps": 15, "quality": 70}
{"action": "input",  "window_id": 12345, "event": {"type": "click", "x": 100, "y": 200, "button": "left"}}
{"action": "stop"}
```

서버 → 클라:
```json
{"type": "windows", "data": [{"id":..., "title":"...", "app_name":"...", "width":..., "height":...}]}
{"type": "frame",   "window_id": ..., "jpeg_b64": "..."}
{"type": "error",   "message": "..."}
```

## 매장 PC 실행

1. Tailscale 켜져 있어야 함 (매장 PC 가상 IP 100.91.100.33 가정)
2. `F:\remote-window\server\run-server.bat` 더블클릭
3. 콘솔에 `WebSocket listening on 0.0.0.0:9001` 뜨면 OK

## Android 폰 사용

1. Tailscale 앱 켜기 (집 폰도 같은 Tailnet)
2. APK 사이드로드 (디버그: `flutter run` 또는 빌드된 APK 직접 설치)
3. RemoteWindow 앱 실행 → 서버 주소 (`100.91.100.33:9001`) → 연결
4. 윈도우 목록에서 클로드 / 업로드 프로그램 선택
5. 화면 탭 = 좌클릭, 더블탭 = 더블클릭, 롱프레스 = 우클릭

## 현재 PoC 한계 (Sprint 3 에서 보완)
- 입력: 좌클릭만 구현. 우클릭/더블클릭/스크롤/드래그/키보드는 미구현
- 인증 없음 (Tailscale Tailnet 내부에서만 접근 가능하다는 전제)
- TLS 없음 (cleartext WebSocket)
- 단일 연결만 지원 (다중 폰 동시 접속 X)
