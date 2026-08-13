@echo off
rem Build Paradroid (BBC Model B) -> PARADROID.SSD
rem
rem   make            assemble to PARADROID.SSD
rem   make run        assemble and launch in b-em
rem
rem Override the tool locations with the BEEBASM and BEM environment variables
rem if yours live somewhere other than the defaults below.

setlocal
set "ROOT=%~dp0"
if not defined BEEBASM set "BEEBASM=%ROOT%bin\beebasm.exe"
if not defined BEM set "BEM=C:\Users\khcon\OneDrive\BEEB\B-Em\b-em-42f6597-w64\b-em.exe"
set "SSD=%ROOT%PARADROID.SSD"

if not exist "%BEEBASM%" (
    echo ERROR: beebasm not found at "%BEEBASM%".
    echo Fetch it from https://github.com/stardot/beebasm and put beebasm.exe in bin\,
    echo or set the BEEBASM environment variable to its location.
    exit /b 1
)

if not exist "%ROOT%src\data\levels.asm" (
    echo ERROR: src\data\ is missing - it is generated, not committed.
    echo Supply paradroid_ce.lst in the project root and run:
    echo     python tools\export_bbc.py
    echo     python tools\export_droids.py
    exit /b 1
)

"%BEEBASM%" -i "%ROOT%src\main.asm" -do "%SSD%" -boot PARA -v > compile.txt
if errorlevel 1 (
    echo beebasm failed.
    exit /b 1
)
echo Built %SSD%

if /i "%~1"=="run" (
    if not exist "%BEM%" (
        echo ERROR: b-em not found at "%BEM%". Set the BEM environment variable.
        exit /b 1
    )
    "%BEM%" -m3 "%SSD%"
)

endlocal
