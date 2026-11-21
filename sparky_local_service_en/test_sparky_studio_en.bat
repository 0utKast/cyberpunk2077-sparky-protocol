@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "PY_EXE="
if exist ".venv\Scripts\python.exe" set "PY_EXE=%~dp0.venv\Scripts\python.exe"
if "%PY_EXE%"=="" if exist "..\sparky_local_service\.venv\Scripts\python.exe" set "PY_EXE=%~dp0..\sparky_local_service\.venv\Scripts\python.exe"
if "%PY_EXE%"=="" (
    echo [ERROR] Python virtual environment .venv not found in sparky_local_service_en or ..\sparky_local_service.
    echo Run 'install_sparky_ai.bat' first to automatically install all local AI dependencies.
    pause
    exit /b 1
)
set PYTHONPATH=%CD%
"%PY_EXE%" -m sparky_rt.gui_studio %*
if errorlevel 1 pause
