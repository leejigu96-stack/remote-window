// 특정 윈도우 캡처 → JPEG 바이트

use anyhow::{anyhow, Result};
use image::{codecs::jpeg::JpegEncoder, ColorType, DynamicImage, RgbaImage};
use xcap::Window;

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
    let (w, h) = (rgba.width(), rgba.height());
    let rgb = DynamicImage::ImageRgba8(rgba).to_rgb8();

    let mut buf = Vec::new();
    let mut encoder = JpegEncoder::new_with_quality(&mut buf, quality);
    encoder.encode(rgb.as_raw(), w, h, ColorType::Rgb8.into())?;

    Ok(buf)
}
