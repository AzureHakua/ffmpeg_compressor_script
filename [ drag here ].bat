@echo off
REM This batch file serves as a wrapper for the PowerShell script
REM It accepts drag and drop operations and passes the file to PowerShell

if "%~1"=="" (
    echo Please drag a video file onto this batch file.
    pause
    exit /b
)

echo Running PowerShell video compressor script...
echo Input file: "%~1"

REM Launch PowerShell with execution policy bypass to run the script
powershell -ExecutionPolicy Bypass -File "%~dp0compress.ps1" -InputFile "%~1"

REM Keep console window open after script finishes
echo.
echo Processing complete. Press any key to exit...
pause > nul