@echo off
REM =============================================================================
REM MECHA SIMULATOR - Windows Build Script
REM Atari 2600 (4K ROM)
REM =============================================================================

echo Building Mecha Simulator...
echo.

REM Check common DASM locations
set DASM_EXE=
if exist "%USERPROFILE%\dasm\dasm.exe" set DASM_EXE=%USERPROFILE%\dasm\dasm.exe
if "%DASM_EXE%"=="" where dasm >nul 2>nul && set DASM_EXE=dasm

if "%DASM_EXE%"=="" (
    echo ERROR: DASM assembler not found
    echo.
    echo Please install DASM from: https://dasm-assembler.github.io/
    echo Or run the PowerShell script to auto-install
    echo.
    pause
    exit /b 1
)

REM Assemble the ROM
"%DASM_EXE%" mecha.asm -f3 -omecha.bin -smecha.sym -lmecha.lst

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful!
    echo Output: mecha.bin
    echo.
    
    REM Show file size
    for %%A in (mecha.bin) do echo ROM size: %%~zA bytes
    echo.
    echo To test, open mecha.bin in Stella or another Atari 2600 emulator.
) else (
    echo.
    echo Build FAILED! Check the errors above.
)

echo.
pause

