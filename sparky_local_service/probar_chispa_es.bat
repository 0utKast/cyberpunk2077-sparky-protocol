@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo [ERROR] Falta el entorno virtual .venv en sparky_local_service.
    echo Ejecuta primero 'instalar_chispa_ia.bat' para instalar automaticamente las dependencias.
    pause
    exit /b 1
)
set PYTHONPATH=%CD%
".venv\Scripts\python.exe" -m chispa_rt.gui_studio %*
if errorlevel 1 pause
