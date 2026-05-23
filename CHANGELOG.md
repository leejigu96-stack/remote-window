# Changelog

## v0.1.0 — 2026-05-23
첫 PoC 릴리즈.

### 기능
- 매장 PC 특정 윈도우 실시간 스트리밍 (15 fps, JPEG, base64 over WebSocket)
- 윈도우 목록 조회 / 선택 / 스트리밍 시작
- 탭 = 좌클릭 (SendInput inject)
- 더블탭 = 더블클릭, 롱프레스 = 우클릭 (이벤트 전송만, 서버 inject 는 Sprint 3)
- **파일/사진 전송**: 갤러리·카메라·일반파일 → 매장 PC `F:\resellonjigu\모바일전송\<날짜>\` 자동 저장
- **셀프 업데이트**: GitHub Releases 에서 최신 버전 체크 + APK 자동 다운로드/설치

### 인프라
- Rust 서버 (axum + xcap + windows-sys)
- Flutter 클라이언트 (Android, release 서명)
- Tailscale 위에서 통신 (cleartext WebSocket — Tailnet 내부 전제)

### 제한사항
- 인증 없음 — Tailscale Tailnet 내부에서만 안전
- 우클릭/스크롤/드래그/키보드 inject 미구현 (Sprint 3)
- 핀치줌 미구현 (Sprint 3)
