// 특정 윈도우 캡처 → JPEG 바이트

use anyhow::{anyhow, Result};
use image::{codecs::jpeg::JpegEncoder, imageops::FilterType, ColorType, DynamicImage, RgbaImage};
use xcap::Window;

/// 최대 폭 (이 이상이면 다운스케일). 폰 화면 1080~1440px 가정 → 1280 이면 충분.
const MAX_WIDTH: u32 = 1280;

pub fn list_windows() -> Result<Vec<(u32, String)>> {
    let windows = Window::all()?;
    Ok(windows
        .into_iter()
        .filter(|w| !w.is_minimized())
        .map(|w| (w.id(), w.title().to_string()))
        .filter(|(_, title)| !title.is_empty())
        .collect())
}

pub fn capture_window_jpeg(window_id: u32, quality: u8) -> Result<Vec<u8>> {
    let windows = Window::all()?;
    let window = windows
        .into_iter()
        .find(|w| w.id() == window_id)
        .ok_or_else(|| anyhow!("window not found: {}", window_id))?;

    // xcap 은 RGBA8 로 반환. JPEG 은 alpha 안 받으니 RGB 로 변환.
    let rgba: RgbaImage = window.capture_image()?;
    let (orig_w, orig_h) = (rgba.width(), rgba.height());

    // 다운스케일 — 폭이 MAX_WIDTH 넘으면 비율 유지하면서 축소
    let (w, h, rgba) = if orig_w > MAX_WIDTH {
        let scale = MAX_WIDTH as f32 / orig_w as f32;
        let nw = MAX_WIDTH;
        let nh = (orig_h as f32 * scale) as u32;
        let scaled = image::imageops::resize(&rgba, nw, nh, FilterType::Triangle);
        (nw, nh, scaled)
    } else {
        (orig_w, orig_h, rgba)
    };

    let rgb = DynamicImage::ImageRgba8(rgba).to_rgb8();

    let mut buf = Vec::new();
    let mut encoder = JpegEncoder::new_with_quality(&mut buf, quality);
    encoder.encode(rgb.as_raw(), w, h, ColorType::Rgb8.into())?;

    Ok(buf)
}
