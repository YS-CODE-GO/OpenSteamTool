@echo off
setlocal EnableDelayedExpansion

REM Repo is UTF-8 without BOM (box-drawing comments etc.).
REM MSVC defaults to system ANSI codepage (936/GBK on zh-CN) without /utf-8,
REM causing C4819 everywhere + spurious C2059/C2143/C2447 in Hooks_Manifest.cpp.
REM VS generator also leaves ExceptionHandling empty (no /EHsc), which breaks
REM toml++ (IPCLoader.cpp C2593: noex::parse_result) on fresh builds.
REM Force both flags for all cl invocations from this script.
REM NOTE: do NOT use -D CMAKE_CXX_FLAGS="/utf-8" here: it overwrites CMake
REM defaults and drops /GR /EHsc etc.
set "CL=/utf-8 /EHsc"

REM Always run from the script directory.
cd /d "%~dp0"

REM ---------------------------------------------------------------------------
REM Configurable build options
REM   GENERATOR  - CMake generator (default: auto-detect)
REM   ARCH       - Architecture for multi-config generators (default: x64)
REM   CONFIGS    - Configurations to build, space-separated (default: Release Debug)
REM ---------------------------------------------------------------------------
if "%GENERATOR%"=="" (
    where ninja >nul 2>nul
    if not errorlevel 1 (
        set "GENERATOR=Ninja Multi-Config"
    ) else (
        set "GENERATOR=Visual Studio 17 2022"
    )
)
if "%ARCH%"=="" set "ARCH=x64"
if "%CONFIGS%"=="" set "CONFIGS=Release Debug"

echo [INFO] Configuring with generator: %GENERATOR%
echo "%GENERATOR%" | findstr /I /C:"Visual Studio" >nul
if not errorlevel 1 (
    cmake -S src -B build -G "%GENERATOR%" -A %ARCH%
) else (
    cmake -S src -B build -G "%GENERATOR%"
)
if errorlevel 1 goto :fail

for %%C in (%CONFIGS%) do (
    echo [INFO] Building: %%C
    cmake --build build --config %%C
    if errorlevel 1 goto :fail

    REM extract_tickets is EXCLUDE_FROM_ALL, so build it explicitly. It lands in
    REM build\tools\%%C\ rather than the shipped output directory.
    REM NOTE: with the Visual Studio generator the target lives in the
    REM separate build\tools solution (top-level .sln only contains
    REM ipc_codegen), so it must be built via build\tools. Ninja keeps a
    REM single graph under build\.
    echo [INFO] Building tool extract_tickets for %%C
    if exist "build\tools\extract_tickets.vcxproj" (
        cmake --build build/tools --config %%C --target extract_tickets
    ) else (
        cmake --build build --config %%C --target extract_tickets
    )
    if errorlevel 1 goto :fail
)

echo [OK] Build completed successfully.
exit /b 0

:fail
echo [ERROR] Build failed.
exit /b 1
