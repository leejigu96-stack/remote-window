@echo off
REM RemoteWindow 서버 — keep-alive 루프
REM 서버가 죽으면 자동으로 다시 시작
REM 부팅 시 자동 실행되도록 작업 스케줄러에 등록 (아래 register-startup.bat 참고)

set "EXE=D:\remote-window_build_target\release\remote-window-server.exe"
set "LOG=D:\remote-window-server.log"
set "RUST_LOG=info"

:loop
echo [%date% %time%] Starting server >> "%LOG%"
"%EXE%" >> "%LOG%" 2>&1
echo [%date% %time%] Server exited with code %ERRORLEVEL%, restarting in 5s >> "%LOG%"
timeout /t 5 /nobreak >nul
goto loop
