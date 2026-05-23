// 모바일 → 매장 PC 파일 업로드 처리
// 흐름:
//   1) 클라가 {action:"upload_start", name, size} 보냄
//   2) 서버가 파일 생성 + state 저장 → {type:"upload_ack", upload_id}
//   3) 클라가 base64 청크 여러 번 보냄: {action:"upload_chunk", upload_id, seq, data_b64}
//      서버는 매 청크마다 진행률 echo: {type:"upload_progress", upload_id, received, total}
//   4) 클라가 {action:"upload_end", upload_id} 보냄 → 서버 close + {type:"upload_done", path}

use anyhow::{anyhow, Result};
use chrono::Local;
use std::collections::HashMap;
use std::fs::{create_dir_all, File};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

pub struct UploadSession {
    pub file: File,
    pub path: PathBuf,
    pub total: u64,
    pub received: u64,
}

pub struct UploadState {
    sessions: Mutex<HashMap<u64, UploadSession>>,
    next_id: Mutex<u64>,
}

impl UploadState {
    pub fn new() -> Self {
        Self {
            sessions: Mutex::new(HashMap::new()),
            next_id: Mutex::new(1),
        }
    }

    pub fn start(&self, name: &str, size: u64) -> Result<(u64, PathBuf)> {
        // 저장 위치: F:\resellonjigu\모바일전송\YYYY-MM-DD\
        let date = Local::now().format("%Y-%m-%d").to_string();
        let base = PathBuf::from(r"F:\resellonjigu\모바일전송").join(&date);
        create_dir_all(&base)?;

        // 파일명 정리: 경로 분리자 제거, 빈 이름 거부
        let clean_name = sanitize(name);
        if clean_name.is_empty() {
            return Err(anyhow!("invalid filename"));
        }

        // 충돌 시 (1) (2) ... suffix
        let mut path = base.join(&clean_name);
        let mut n = 1;
        while path.exists() {
            let stem = std::path::Path::new(&clean_name)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("file");
            let ext = std::path::Path::new(&clean_name)
                .extension()
                .and_then(|s| s.to_str())
                .map(|s| format!(".{}", s))
                .unwrap_or_default();
            path = base.join(format!("{} ({}){}", stem, n, ext));
            n += 1;
        }

        let file = File::create(&path)?;

        let mut id_guard = self.next_id.lock().unwrap();
        let id = *id_guard;
        *id_guard += 1;
        drop(id_guard);

        self.sessions.lock().unwrap().insert(
            id,
            UploadSession {
                file,
                path: path.clone(),
                total: size,
                received: 0,
            },
        );
        Ok((id, path))
    }

    /// returns (received, total)
    pub fn chunk(&self, id: u64, data: &[u8]) -> Result<(u64, u64)> {
        let mut sessions = self.sessions.lock().unwrap();
        let s = sessions
            .get_mut(&id)
            .ok_or_else(|| anyhow!("upload session not found: {}", id))?;
        s.file.write_all(data)?;
        s.received += data.len() as u64;
        Ok((s.received, s.total))
    }

    /// returns saved path
    pub fn end(&self, id: u64) -> Result<PathBuf> {
        let mut sessions = self.sessions.lock().unwrap();
        let mut s = sessions
            .remove(&id)
            .ok_or_else(|| anyhow!("upload session not found: {}", id))?;
        s.file.flush()?;
        Ok(s.path)
    }
}

fn sanitize(name: &str) -> String {
    // 경로 구분자, 제어 문자 제거
    name.chars()
        .filter(|c| !matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|'))
        .filter(|c| !c.is_control())
        .collect::<String>()
        .trim()
        .to_string()
}
