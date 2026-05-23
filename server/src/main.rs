// Remote Window Server (매장 PC 측)
// - Tailscale 가상 IP에서 WebSocket 서버
// - 특정 윈도우 캡처 → JPEG → 송출 (15~30 fps)
// - 모바일 입력 수신 → SendInput으로 윈도우에 inject

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod capture;      // 윈도우 캡처
mod inject;       // 입력 inject
mod ws;           // WebSocket 서버
mod windows_list; // 사용 가능 윈도우 목록
mod upload;       // 모바일 → PC 파일 업로드

use anyhow::Result;
use tracing::info;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    info!("Remote Window Server 시작");

    // Tailscale 가상 IP 또는 0.0.0.0 바인딩
    // 운영 시: 100.91.100.33:9001 만 listen (외부 노출 0)
    let bind_addr = "0.0.0.0:9001";
    ws::run_server(bind_addr).await?;

    Ok(())
}
