// 모바일 입력 이벤트 → 매장 PC 특정 윈도우에 SendInput

use anyhow::Result;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum InputEvent {
    Click { x: i32, y: i32, button: MouseButton },
    DoubleClick { x: i32, y: i32 },
    LongPress { x: i32, y: i32 }, // → 우클릭
    Scroll { x: i32, y: i32, delta_x: i32, delta_y: i32 },
    Drag { from_x: i32, from_y: i32, to_x: i32, to_y: i32 },
    Key { text: String }, // 텍스트 입력
    KeyCombo { keys: Vec<String> }, // 예: ["ctrl", "c"]
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MouseButton {
    Left,
    Right,
    Middle,
}

#[cfg(windows)]
pub fn dispatch(window_id: u32, event: InputEvent) -> Result<()> {
    use windows_sys::Win32::Foundation::{HWND, POINT};
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        SetForegroundWindow, GetWindowRect,
    };

    // 윈도우 핸들 얻기
    let hwnd: HWND = window_id as HWND;

    // 윈도우 좌표 → 스크린 좌표 변환
    let mut rect = unsafe { std::mem::zeroed() };
    unsafe {
        GetWindowRect(hwnd, &mut rect);
        SetForegroundWindow(hwnd);
    }

    // TODO: 각 이벤트별 INPUT 구조체 채워서 SendInput 호출
    // 이번 PoC에선 Click(left)만 우선 구현. 나머지는 Sprint 3에서.

    match event {
        InputEvent::Click { x, y, button: MouseButton::Left } => {
            // 윈도우 내 상대 좌표 → 절대 스크린 좌표
            let abs_x = rect.left + x;
            let abs_y = rect.top + y;
            unsafe {
                let mut p = POINT { x: abs_x, y: abs_y };
                // 마우스 이동 + 좌클릭
                let inputs = [
                    INPUT {
                        r#type: INPUT_MOUSE,
                        Anonymous: INPUT_0 {
                            mi: MOUSEINPUT {
                                dx: (p.x * 65535 / get_screen_width()) as i32,
                                dy: (p.y * 65535 / get_screen_height()) as i32,
                                mouseData: 0,
                                dwFlags: MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE,
                                time: 0,
                                dwExtraInfo: 0,
                            },
                        },
                    },
                    INPUT {
                        r#type: INPUT_MOUSE,
                        Anonymous: INPUT_0 {
                            mi: MOUSEINPUT {
                                dx: 0,
                                dy: 0,
                                mouseData: 0,
                                dwFlags: MOUSEEVENTF_LEFTDOWN,
                                time: 0,
                                dwExtraInfo: 0,
                            },
                        },
                    },
                    INPUT {
                        r#type: INPUT_MOUSE,
                        Anonymous: INPUT_0 {
                            mi: MOUSEINPUT {
                                dx: 0,
                                dy: 0,
                                mouseData: 0,
                                dwFlags: MOUSEEVENTF_LEFTUP,
                                time: 0,
                                dwExtraInfo: 0,
                            },
                        },
                    },
                ];
                SendInput(
                    inputs.len() as u32,
                    inputs.as_ptr(),
                    std::mem::size_of::<INPUT>() as i32,
                );
            }
        }
        _ => {
            // 다른 이벤트는 Sprint 3에서 구현
            tracing::warn!("not yet implemented: {:?}", event);
        }
    }
    Ok(())
}

#[cfg(windows)]
fn get_screen_width() -> i32 {
    use windows_sys::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_CXSCREEN};
    unsafe { GetSystemMetrics(SM_CXSCREEN) }
}

#[cfg(windows)]
fn get_screen_height() -> i32 {
    use windows_sys::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_CYSCREEN};
    unsafe { GetSystemMetrics(SM_CYSCREEN) }
}

#[cfg(not(windows))]
pub fn dispatch(_window_id: u32, _event: InputEvent) -> Result<()> {
    Err(anyhow::anyhow!("inject only on Windows"))
}
