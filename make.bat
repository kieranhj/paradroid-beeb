@echo off
rem make.bat - the build, for anyone who types `make`. A thin wrapper
rem over build.ps1, which is the build itself; arguments pass through,
rem so `make -Run` assembles and launches b-em exactly as
rem `.\build.ps1 -Run` does. make.sh is the same wrapper for a POSIX
rem shell. Keep all three in step.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %ERRORLEVEL%
