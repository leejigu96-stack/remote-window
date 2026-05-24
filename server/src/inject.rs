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
    Key { text: String }, // 유니코드 텍스트 입력
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
    use windows_sys::Win32::Foundation::HWND;
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
    use windows_sys::Win32::UI::WindowsAndMessaging::{GetWindowRect, SetForegroundWindow};

    let hwnd: HWND = window_id as HWND;
    let mut rect = unsafe { std::mem::zeroed() };
    unsafe {
        GetWindowRect(hwnd, &mut rect);
        SetForegroundWindow(hwnd);
    }

    let sw = get_screen_width();
    let sh = get_screen_height().max(1);

    // 윈도우 내 상대 좌표 (x, y) → 화면 절대 좌표 정규화 (0~65535)
    let to_abs = |x: i32, y: i32| -> (i32, i32) {
        let abs_x = rect.left + x;
        let abs_y = rect.top + y;
        (abs_x * 65535 / sw.max(1), abs_y * 65535 / sh.max(1))
    };

    let mouse_input = |dx: i32, dy: i32, flags: MOUSE_EVENT_FLAGS, data: i32| INPUT {
        r#type: INPUT_MOUSE,
        Anonymous: INPUT_0 {
            mi: MOUSEINPUT {
                dx,
                dy,
                mouseData: data as u32,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: 0,
            },
        },
    };

    let send = |inputs: &[INPUT]| unsafe {
        SendInput(
            inputs.len() as u32,
            inputs.as_ptr(),
            std::mem::size_of::<INPUT>() as i32,
        );
    };

    match event {
        InputEvent::Click { x, y, button } => {
            let (ax, ay) = to_abs(x, y);
            let (down, up) = match button {
                MouseButton::Left => (MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP),
                MouseButton::Right => (MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP),
                MouseButton::Middle => (MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP),
            };
            let inputs = [
                mouse_input(ax, ay, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, 0),
                mouse_input(0, 0, down, 0),
                mouse_input(0, 0, up, 0),
            ];
            send(&inputs);
        }
        InputEvent::DoubleClick { x, y } => {
            let (ax, ay) = to_abs(x, y);
            let inputs = [
                mouse_input(ax, ay, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, 0),
                mouse_input(0, 0, MOUSEEVENTF_LEFTDOWN, 0),
                mouse_input(0, 0, MOUSEEVENTF_LEFTUP, 0),
                mouse_input(0, 0, MOUSEEVENTF_LEFTDOWN, 0),
                mouse_input(0, 0, MOUSEEVENTF_LEFTUP, 0),
            ];
            send(&inputs);
        }
        InputEvent::LongPress { x, y } => {
            // 모바일 롱프레스 → 우클릭
            let (ax, ay) = to_abs(x, y);
            let inputs = [
                mouse_input(ax, ay, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, 0),
                mouse_input(0, 0, MOUSEEVENTF_RIGHTDOWN, 0),
                mouse_input(0, 0, MOUSEEVENTF_RIGHTUP, 0),
            ];
            send(&inputs);
        }
        InputEvent::Scroll { x, y, delta_x: _, delta_y } => {
            let (ax, ay) = to_abs(x, y);
            // WHEEL 단위: 120 = 한 줄
            let scroll_amt = delta_y.signum() * delta_y.abs().min(600);
            let inputs = [
                mouse_input(ax, ay, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, 0),
                mouse_input(0, 0, MOUSEEVENTF_WHEEL, scroll_amt),
            ];
            send(&inputs);
        }
        InputEvent::Drag { from_x, from_y, to_x, to_y } => {
            let (fax, fay) = to_abs(from_x, from_y);
            let (tax, tay) = to_abs(to_x, to_y);
            let inputs = [
                mouse_input(fax, fay, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, 0),
                mouse_input(0, 0, MOUSEEVENTF_LEFTDOWN, 0),
                mouse_input(tax, tay, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, 0),
                mouse_input(0, 0, MOUSEEVENTF_LEFTUP, 0),
            ];
            send(&inputs);
        }
        InputEvent::Key { text } => {
            // 유니코드 문자 한 글자씩 KEYEVENTF_UNICODE 로 입력.
            // BMP 외 문자 (예: 이모지) 는 surrogate 쌍으로 자동 분해됨.
            for code_unit in text.encode_utf16() {
                let down = INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: 0,
                            wScan: code_unit,
                            dwFlags: KEYEVENTF_UNICODE,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                };
                let up = INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: 0,
                            wScan: code_unit,
                            dwFlags: KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                };
                send(&[down, up]);
            }
        }
        InputEvent::KeyCombo { keys } => {
            // 예: ["ctrl", "c"] / ["alt", "tab"] / ["enter"]
            let vks: Vec<u16> = keys.iter().filter_map(|k| name_to_vk(k)).collect();
            if vks.is_empty() {
                tracing::warn!("KeyCombo: 알 수 없는 키 {:?}", keys);
                return Ok(());
            }
            // 한 번의 SendInput 호출로 down + up 전부 — Windows 가 atomicity 보장
            let mut inputs: Vec<INPUT> = Vec::with_capacity(vks.len() * 2);
            for vk in &vks {
                inputs.push(INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: *vk,
                            wScan: 0,
                            dwFlags: 0,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                });
            }
            for vk in vks.iter().rev() {
                inputs.push(INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: *vk,
                            wScan: 0,
                            dwFlags: KEYEVENTF_KEYUP,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                });
            }
            send(&inputs);
        }
    }
    Ok(())
}

#[cfg(windows)]
fn name_to_vk(name: &str) -> Option<u16> {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
    match name.to_lowercase().as_str() {
        "ctrl" | "control" => Some(VK_CONTROL),
        "alt" => Some(VK_MENU),
        "shift" => Some(VK_SHIFT),
        "win" | "meta" => Some(VK_LWIN),
        "enter" | "return" => Some(VK_RETURN),
        "tab" => Some(VK_TAB),
        "esc" | "escape" => Some(VK_ESCAPE),
        "backspace" | "back" => Some(VK_BACK),
        "delete" | "del" => Some(VK_DELETE),
        "space" => Some(VK_SPACE),
        "up" => Some(VK_UP),
        "down" => Some(VK_DOWN),
        "left" => Some(VK_LEFT),
        "right" => Some(VK_RIGHT),
        "home" => Some(VK_HOME),
        "end" => Some(VK_END),
        "pageup" | "pgup" => Some(VK_PRIOR),
        "pagedown" | "pgdn" => Some(VK_NEXT),
        // a-z, 0-9 (ASCII 직접)
        c if c.len() == 1 => {
            let ch = c.chars().next().unwrap().to_ascii_uppercase();
            if ch.is_ascii_alphanumeric() {
                Some(ch as u16)
            } else {
                None
            }
        }
        _ => None,
    }
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
