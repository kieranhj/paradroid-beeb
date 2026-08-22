@echo off
rem make.bat - the build, for anyone who types `make`. A thin wrapper
rem over build.ps1, which is the build itself (briefing convert,
rem beebasm, make_disc); nothing here needs keeping in step beyond the
rem argument mapping. `make run` (this script's old convention) and
rem `make -Run` both assemble and launch b-em. make.sh is the same
rem wrapper for a POSIX shell.
setlocal
set "ARGS=%*"
if /i "%~1"=="run" set "ARGS=-Run"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %ARGS%
exit /b %ERRORLEVEL%
