@echo off
REM RemoteWindow 서버 실행 스크립트 (매장 PC)
REM 사용: 더블클릭하면 백그라운드 실행됨 (RUST_LOG=info)

set "CARGO_HOME=D:\resellon_dev\cargo"
set "RUSTUP_HOME=D:\resellon_dev\rustup"
set "CARGO_TARGET_DIR=D:\remote-window_build_target"
set "PATH=%CARGO_HOME%\bin;%PATH%"
set "RUST_LOG=info"

cd /d F:\remote-window\server
cargo run --release
