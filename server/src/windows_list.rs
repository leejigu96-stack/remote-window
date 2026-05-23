// 매장 PC 활성 윈도우 목록 + 메타데이터

use anyhow::Result;
use serde::Serialize;
use xcap::Window;

#[derive(Debug, Serialize, Clone)]
pub struct WindowInfo {
    pub id: u32,
    pub title: String,
    pub app_name: String,
    pub width: u32,
    pub height: u32,
    pub is_minimized: bool,
}

pub fn list_visible_windows() -> Result<Vec<WindowInfo>> {
    let windows = Window::all()?;
    let mut infos = Vec::new();
    for w in windows {
        let title = w.title().to_string();
        if title.is_empty() {
            continue;
        }
        let is_minimized = w.is_minimized();
        if is_minimized {
            continue;
        }
        infos.push(WindowInfo {
            id: w.id(),
            title,
            app_name: w.app_name().to_string(),
            width: w.width(),
            height: w.height(),
            is_minimized,
        });
    }
    Ok(infos)
}
