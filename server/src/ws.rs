// WebSocket 서버 — 모바일과 통신
// 프로토콜:
//   클라이언트 → 서버 :
//     { "action": "list_windows" }
//     { "action": "stream", "window_id": 12345, "fps": 15, "quality": 70 }
//     { "action": "input", "window_id": 12345, "event": {...} }
//     { "action": "stop" }
//     { "action": "upload_start", "name": "photo.jpg", "size": 1234567 }
//     { "action": "upload_chunk", "upload_id": 1, "seq": 0, "data_b64": "..." }
//     { "action": "upload_end",   "upload_id": 1 }
//   서버 → 클라이언트:
//     { "type": "windows", "data": [...] }
//     { "type": "frame", "window_id": ..., "jpeg_b64": "..." }
//     { "type": "error", "message": "..." }
//     { "type": "upload_ack", "upload_id": 1, "path": "..." }
//     { "type": "upload_progress", "upload_id": 1, "received": 1024, "total": 1234567 }
//     { "type": "upload_done", "upload_id": 1, "path": "..." }

use crate::{capture, inject, upload::UploadState, windows_list};
use anyhow::Result;
use axum::{
    extract::{ws::{Message, WebSocket, WebSocketUpgrade}, State},
    response::IntoResponse,
    routing::get,
    Router,
};
use base64::Engine;
use futures::{SinkExt, StreamExt};
use serde::Deserialize;
use std::sync::Arc;
use std::time::Duration;
use tracing::{error, info, warn};

#[derive(Debug, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
enum ClientMsg {
    ListWindows,
    Stream { window_id: u32, fps: u32, quality: u8 },
    Input { window_id: u32, event: inject::InputEvent },
    Stop,
    UploadStart { name: String, size: u64 },
    UploadChunk {
        upload_id: u64,
        #[allow(dead_code)]
        seq: u64,
        data_b64: String,
    },
    UploadEnd { upload_id: u64 },
}

pub async fn run_server(addr: &str) -> Result<()> {
    let state = Arc::new(UploadState::new());
    let app = Router::new()
        .route("/ws", get(ws_handler))
        .with_state(state);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    info!("WebSocket listening on {}", addr);
    axum::serve(listener, app).await?;
    Ok(())
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<UploadState>>,
) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: Arc<UploadState>) {
    info!("client connected");
    let (mut sender, mut receiver) = socket.split();

    let mut stream_task: Option<tokio::task::JoinHandle<()>> = None;
    let (frame_tx, mut frame_rx) = tokio::sync::mpsc::unbounded_channel::<Message>();

    let outbound = tokio::spawn(async move {
        while let Some(msg) = frame_rx.recv().await {
            if sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    while let Some(Ok(msg)) = receiver.next().await {
        match msg {
            Message::Text(txt) => {
                let parsed: Result<ClientMsg, _> = serde_json::from_str(&txt);
                match parsed {
                    Ok(ClientMsg::ListWindows) => {
                        let list = windows_list::list_visible_windows().unwrap_or_default();
                        let resp = serde_json::json!({"type":"windows","data":list});
                        let _ = frame_tx.send(Message::Text(resp.to_string()));
                    }
                    Ok(ClientMsg::Stream { window_id, fps, quality }) => {
                        if let Some(h) = stream_task.take() {
                            h.abort();
                        }
                        let tx = frame_tx.clone();
                        let handle = tokio::spawn(async move {
                            let interval = Duration::from_millis(1000 / fps.max(1) as u64);
                            loop {
                                match capture::capture_window_jpeg(window_id, quality) {
                                    Ok(bytes) => {
                                        // 바이너리 프레임 그대로 (base64 X)
                                        if tx.send(Message::Binary(bytes)).is_err() {
                                            break;
                                        }
                                    }
                                    Err(e) => {
                                        error!("capture err: {}", e);
                                        let msg = serde_json::json!({
                                            "type":"error",
                                            "message": format!("{}", e)
                                        });
                                        let _ = tx.send(Message::Text(msg.to_string()));
                                        break;
                                    }
                                }
                                tokio::time::sleep(interval).await;
                            }
                        });
                        stream_task = Some(handle);
                    }
                    Ok(ClientMsg::Input { window_id, event }) => {
                        if let Err(e) = inject::dispatch(window_id, event) {
                            warn!("inject err: {}", e);
                        }
                    }
                    Ok(ClientMsg::Stop) => {
                        if let Some(h) = stream_task.take() {
                            h.abort();
                        }
                    }
                    Ok(ClientMsg::UploadStart { name, size }) => {
                        match state.start(&name, size) {
                            Ok((id, path)) => {
                                info!("upload start id={} name={} size={} path={:?}", id, name, size, path);
                                let resp = serde_json::json!({
                                    "type":"upload_ack",
                                    "upload_id": id,
                                    "path": path.to_string_lossy(),
                                });
                                let _ = frame_tx.send(Message::Text(resp.to_string()));
                            }
                            Err(e) => {
                                let resp = serde_json::json!({"type":"error","message":format!("upload_start: {}",e)});
                                let _ = frame_tx.send(Message::Text(resp.to_string()));
                            }
                        }
                    }
                    Ok(ClientMsg::UploadChunk { upload_id, data_b64, .. }) => {
                        match base64::engine::general_purpose::STANDARD.decode(&data_b64) {
                            Ok(bytes) => match state.chunk(upload_id, &bytes) {
                                Ok((received, total)) => {
                                    let resp = serde_json::json!({
                                        "type":"upload_progress",
                                        "upload_id": upload_id,
                                        "received": received,
                                        "total": total
                                    });
                                    let _ = frame_tx.send(Message::Text(resp.to_string()));
                                }
                                Err(e) => {
                                    let resp = serde_json::json!({"type":"error","message":format!("upload_chunk: {}",e)});
                                    let _ = frame_tx.send(Message::Text(resp.to_string()));
                                }
                            },
                            Err(e) => {
                                let resp = serde_json::json!({"type":"error","message":format!("b64 decode: {}",e)});
                                let _ = frame_tx.send(Message::Text(resp.to_string()));
                            }
                        }
                    }
                    Ok(ClientMsg::UploadEnd { upload_id }) => {
                        match state.end(upload_id) {
                            Ok(path) => {
                                info!("upload done id={} path={:?}", upload_id, path);
                                let resp = serde_json::json!({
                                    "type":"upload_done",
                                    "upload_id": upload_id,
                                    "path": path.to_string_lossy(),
                                });
                                let _ = frame_tx.send(Message::Text(resp.to_string()));
                            }
                            Err(e) => {
                                let resp = serde_json::json!({"type":"error","message":format!("upload_end: {}",e)});
                                let _ = frame_tx.send(Message::Text(resp.to_string()));
                            }
                        }
                    }
                    Err(e) => warn!("parse err: {}", e),
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    if let Some(h) = stream_task {
        h.abort();
    }
    outbound.abort();
    info!("client disconnected");
}
