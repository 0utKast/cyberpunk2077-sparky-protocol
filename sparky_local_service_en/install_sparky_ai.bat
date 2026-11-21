@echo off
chcp 65001 >nul
cd /d "%~dp0"
setlocal EnableDelayedExpansion

echo ============================================================================
echo   S.P.A.R.K.Y. v2.0 — One-Click Local AI Service Installer (EN)
echo ============================================================================
echo.

set "PY_CMD="
py -3.12 -V >nul 2>&1
if not errorlevel 1 set "PY_CMD=py -3.12"
if "%PY_CMD%"=="" (
    py -3.11 -V >nul 2>&1
    if not errorlevel 1 set "PY_CMD=py -3.11"
)
if "%PY_CMD%"=="" (
    python --version >nul 2>&1
    if not errorlevel 1 set "PY_CMD=python"
)
if "%PY_CMD%"=="" (
    echo [ERROR] Python 3.11 or 3.12 was not found on your system.
    echo Download and install Python 3.12 from https://www.python.org/downloads/
    pause
    exit /b 1
)

echo [1/4] Using Python interpreter: %PY_CMD%
if not exist ".venv\Scripts\python.exe" (
    echo [1/4] Creating virtual environment .venv...
    %PY_CMD% -m venv .venv
    if errorlevel 1 (
        echo [ERROR] Failed to create .venv. Please make sure Python 3.11 or 3.12 is used.
        pause
        exit /b 1
    )
) else (
    echo [1/4] Existing virtual environment .venv found.
)

echo [2/4] Upgrading pip and installing PyTorch...
".venv\Scripts\python.exe" -m pip install --upgrade pip
if errorlevel 1 (
    echo [ERROR] Failed to upgrade pip.
    pause
    exit /b 1
)

nvidia-smi >nul 2>&1
if not errorlevel 1 (
    echo       NVIDIA GPU detected: installing PyTorch with CUDA support ^(cu124^)...
    ".venv\Scripts\pip.exe" install torch torchaudio --index-url https://download.pytorch.org/whl/cu124
) else (
    echo       No NVIDIA GPU detected ^(or nvidia-smi unavailable^): installing CPU PyTorch...
    ".venv\Scripts\pip.exe" install torch torchaudio
)
if errorlevel 1 (
    echo [ERROR] PyTorch installation failed.
    pause
    exit /b 1
)

echo [3/4] Installing S.P.A.R.K.Y. v2.0 ^(F5-TTS, Kokoro ONNX, Hybrid RAG, Studio GUI^)...
".venv\Scripts\pip.exe" install -e .
if errorlevel 1 (
    echo [ERROR] Dependency installation from pyproject.toml failed.
    pause
    exit /b 1
)

echo [4/4] Checking Ollama and pulling default conversational model...
where ollama >nul 2>&1
if errorlevel 1 (
    echo [WARNING] 'ollama' was not found in your PATH.
    echo           Install Ollama from https://ollama.com/download and then run:
    echo           ollama pull gemma3:12b   ^(or 'ollama pull gemma3:4b' on GPUs under 10 GB VRAM^)
) else (
    echo       Pulling/verifying default model gemma3:12b...
    echo       ^(Tip: for 8 GB VRAM GPUs or lower, you can pull 'gemma3:4b' and switch inside SPARKY Studio^)
    ollama pull gemma3:12b
)

echo.
echo ============================================================================
echo   SETUP COMPLETE!
echo   1. Open 'test_sparky_studio_en.bat' to select speakers, voice, or reactions.
echo   2. Run 'start_sparky_service.bat' while playing Cyberpunk 2077.
echo ============================================================================
pause
