@echo off
chcp 65001 >nul
cd /d "%~dp0"
setlocal EnableDelayedExpansion

echo ============================================================================
echo   C.H.I.S.P.A. v2.0 — Instalador Automatico del Servicio IA Local (ES)
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
    echo [ERROR] No se encontro Python 3.11 o 3.12 instalado en el sistema.
    echo Descarga e instala Python 3.12 desde https://www.python.org/downloads/
    pause
    exit /b 1
)

echo [1/4] Usando interprete: %PY_CMD%
if not exist ".venv\Scripts\python.exe" (
    echo [1/4] Creando entorno virtual .venv...
    %PY_CMD% -m venv .venv
    if errorlevel 1 (
        echo [ERROR] Fallo al crear .venv. Verifica que uses Python 3.11 o 3.12.
        pause
        exit /b 1
    )
) else (
    echo [1/4] Entorno virtual .venv detectado.
)

echo [2/4] Actualizando pip e instalando PyTorch...
".venv\Scripts\python.exe" -m pip install --upgrade pip
if errorlevel 1 (
    echo [ERROR] Fallo al actualizar pip.
    pause
    exit /b 1
)

nvidia-smi >nul 2>&1
if not errorlevel 1 (
    echo       GPU NVIDIA detectada: instalando PyTorch con aceleracion CUDA ^(cu124^)...
    ".venv\Scripts\pip.exe" install torch torchaudio --index-url https://download.pytorch.org/whl/cu124
) else (
    echo       No se detecto GPU NVIDIA ^(o nvidia-smi no disponible^): instalando PyTorch CPU...
    ".venv\Scripts\pip.exe" install torch torchaudio
)
if errorlevel 1 (
    echo [ERROR] Fallo instalando PyTorch.
    pause
    exit /b 1
)

echo [3/4] Instalando C.H.I.S.P.A. v2.0 ^(F5-TTS, Kokoro ONNX, RAG Hibrido, GUI Studio^)...
".venv\Scripts\pip.exe" install -e .
if errorlevel 1 (
    echo [ERROR] Fallo instalando dependencias en pyproject.toml.
    pause
    exit /b 1
)

echo [4/4] Comprobando Ollama y modelo conversacional...
where ollama >nul 2>&1
if errorlevel 1 (
    echo [AVISO] No se encontro 'ollama' en tu PATH.
    echo         Instala Ollama desde https://ollama.com/download y luego ejecuta:
    echo         ollama pull gemma3:12b   ^(o 'ollama pull gemma3:4b' en GPUs menores de 10 GB VRAM^)
) else (
    echo       Descargando/verificando modelo por defecto gemma3:12b...
    echo       ^(Consejo: en GPUs de 8 GB VRAM o menos, usa 'ollama pull gemma3:4b' desde Chispa Studio^)
    ollama pull gemma3:12b
)

echo.
echo ============================================================================
echo   INSTALACION COMPLETADA CON EXITO
echo   1. Abre 'probar_chispa_es.bat' para elegir altavoz, voz o reacciones.
echo   2. Ejecuta 'iniciar_servicio_chispa.bat' mientras juegas a Cyberpunk 2077.
echo ============================================================================
pause
