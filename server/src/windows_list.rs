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
        if w.is_minimized() {
            continue;
        }
        let width = w.width();
        let height = w.height();
        // 너무 작은 윈도우 (시스템 트레이, 숨김 컨테이너, 툴팁 등) 제외
        if width < 300 || height < 200 {
            continue;
        }
        // 시스템/내부 윈도우 필터
        let app_name = w.app_name().to_string();
        let title_lower = title.to_lowercase();
        let app_lower = app_name.to_lowercase();
        if matches!(
            app_lower.as_str(),
            "explorer.exe" | "applicationframehost.exe" | "textinputhost.exe"
        ) && (title_lower == "program manager"
            || title_lower == "settings"
            || title_lower.starts_with("microsoft text input"))
        {
            continue;
        }
        infos.push(WindowInfo {
            id: w.id(),
            title,
            app_name,
            width,
            height,
            is_minimized: false,
        });
    }
    Ok(infos)
}
