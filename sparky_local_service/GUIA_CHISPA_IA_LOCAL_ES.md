# C.H.I.S.P.A. v2.0 — Guía Completa de IA Local, Enciclopedia Cyberpunk y Memoria

> **Edición en Español — 100 % Local y Offline por defecto**  
> Ejecuta el cerebro conversacional (`gemma3:12b` en Ollama con reparto automático de VRAM, o `gemma3:4b` como alternativa ligera) y la voz en tiempo real (`F5-Spanish` en GPU o `Kokoro` en CPU) directamente en tu equipo, con búsqueda híbrida de lore en CPU (`0 MB` de VRAM extra) y memoria persistente aislada por partida.

---

## 1. Instalación rápida y cómo iniciar C.H.I.S.P.A. v2.0

1. **Instalación automática en un clic (primera vez):**
   - Asegúrate de tener instalado [Python 3.11 o 3.12](https://www.python.org/downloads/) y [Ollama](https://ollama.com/download).
   - Ejecuta **`instalar_chispa_ia.bat`** dentro de `sparky_local_service\`: crea `.venv`, detecta GPU NVIDIA (`cu124`) o CPU, instala dependencias y descarga `gemma3:12b`.
2. **Para jugar dentro de Cyberpunk 2077 (enlace en directo por Kiroshi):**
   - Ejecuta **`iniciar_servicio_chispa.bat`** dentro de `sparky_local_service\` y deja esa ventana abierta o minimizada mientras juegas.
   - El servicio **detecta automáticamente** la carpeta de **Cyberpunk 2077** en **Steam, GOG o Epic Games** (o usa `%USERPROFILE%\.chispa_ai_bridge\game_path.txt` / `--ipc-dir` si usas una ruta personalizada).
   - Al cargar tu partida en Cyberpunk 2077 verás el estado **`● IA LOCAL EN LÍNEA`** al abrir la barra de diálogo.
3. **Para probar voz, elegir altavoces y configurar opciones (`Chispa Studio`):**
   - Ejecuta **`probar_chispa_es.bat`**.
   - Desde **Chispa Studio** puedes seleccionar tu altavoz real (por WASAPI), cambiar el motor de voz, cambiar entre `gemma3:12b` / `gemma3:4b`, probar conversaciones escritas con respuesta hablada, ajustar el **modo de reacciones espontáneas**, **borrar la memoria de partida** o activar/desactivar el permiso de consulta online.

---

## 2. Controles dentro de Cyberpunk 2077 (Barra Neural Kiroshi)

| Tecla | Acción |
| :--- | :--- |
| **`Y`** | Abre la **Barra Neural Kiroshi** integrada en el HUD inferior para escribir libremente a C.H.I.S.P.A. |
| **`Enter`** | Envía tu mensaje a C.H.I.S.P.A. (si estaba hablando de forma espontánea, te cede la palabra al instante). |
| **`Tab`** | Solicita un análisis táctico rápido de la situación actual sin escribir. |
| **`↑`** (Flecha arriba) | Recupera el último mensaje que escribiste. |
| **`Esc`** | Cancela y cierra la barra sin enviar nada. |
| **`U`** | Dispara directamente desde el juego una **réplica táctica rápida en vivo** (analiza distrito, misión seguida, blanco escaneado, salud, arma y alertas NCPD). |

> **Nota sobre escenas e inmersión:** C.H.I.S.P.A. detecta automáticamente llamadas vanilla, escenas cinemáticas, diálogos activos, menús y lectura de pinchos (*Shards*), cortando o pausando su voz de inmediato para no pisar nunca el audio del juego.

---

## 3. Enciclopedia Híbrida del Universo Cyberpunk (RAG Local `0 MB` VRAM)

C.H.I.S.P.A. integra una enciclopedia modular propia de **162 fichas** organizada en `sparky_local_service/chispa_rt/lore_kb/`:

- **Identidad y Campaña Temporada 1 (`01_chispa_identidad_y_temporada1.json`):** Su origen en Zetatech (2022), los 55 años encerrado y los Episodios 0–5 (incluidos los 3 desenlaces de Pacífico).
- **Historia y Red 1990–2077 (`02_historia_y_red_1990_2077.json`):** Richard Night, el Colapso, las 4 Guerras Corporativas, Rache Bartmoss y el DataKrash (2022), asalto a la Torre Arasaka (2023), la Era del Rojo, Muro Negro, Soulkiller/Mikoshi, Guerra de Unificación y *Edgerunners* (David Martinez, Lucy y Rebecca).
- **Corporaciones, Bandas, Distritos, Personajes, Arsenal y Guías (`03`–`08`):** Arasaka, Militech, Zetatech, Kang Tao, Biotechnica (`CHOOH2`), Night Corp, Trauma Team, NetWatch, MaxTac, todas las bandas y clanes nómadas, todos los distritos de Night City + Dogtown + Badlands, Fixers, armas Power/Tech/Smart, ciberware, quickhacks y guías tácticas de misiones.

### Cómo combina precisión, idioma y protección anti-spoilers
1. **Búsqueda híbrida de 3 vías en `< 5 ms` (`0 MB` VRAM GPU):**
   - **Anclaje Kiroshi:** lee de `state.json` tu distrito, misión seguida (`JournalManager.GetTrackedEntry`), enemigo recién escaneado y último pincho leído.
   - **Índice léxico `SQLite FTS5` (BM25):** clava siglas, códigos de misión y términos exactos en español e inglés.
   - **Vectores semánticos multilingües en CPU (`ONNX`):** encuentra respuestas aunque uses sinónimos en español mientras el cliente del juego esté configurado en inglés.
2. **Perspectiva temporal (`2022` vs `2077`) y escudo anti-spoilers:**
   - Separa recuerdos directos previos al DataKrash (2022) de la inteligencia consultada vía Kiroshi en 2077.
   - Si V aún está en el **Acto 1** antes de completar El Golpe, bloquea automáticamente fichas con spoilers del Acto 2+ (engrama de Johnny, Relic dañado, Dogtown, finales). *(Nota: debido al extenso archivo histórico 2022–2077 de C.H.I.S.P.A., preguntarle directamente por grandes misterios del trasfondo de Night City puede seguir desvelando algún «spoiler» de lore general de forma anticipada.)*
3. **Añadir tus propias fichas personalizadas:**
   - Crea o edita `%USERPROFILE%\.chispa_ai_bridge\custom_lore_es.json` siguiendo el mismo formato JSON de `lore_kb/*.json` (`id`, `title`, `keywords_es`, `keywords_en`, `content`, `era`, `min_act`) y se indexará automáticamente al arrancar.

---

## 4. Memoria Episódica Aislada por Partida

El sistema guarda en `%USERPROFILE%\.chispa_ai_bridge\state\` tu historial completamente aislado por personaje y partida (`profile_<pasado>_<mem_uid>.json` + `episodic_index_es.sqlite`):

- **Cero fugas entre partidas guardadas:** Cada campaña genera un sello persistente `chispa_mem_uid` único y marca cada turno con `playthrough_sec` para filtrar recuerdos futuros si recargas un punto anterior.
- **Recuerdos recuperables a largo plazo:** Tanto tus charlas manuales como los sucesos clave y el texto de los **pinchos (*Shards*)** que lees en el juego se indexan para poder comentarlos horas después.
- **Compresión asíncrona en segundo plano:** Cada 8 turnos, un hilo secundario condensa un diario en 1.ª persona de hasta 15 hitos y evoluciona el nivel de camaradería/sincronización con V sin añadir latencia al turno actual.
- **Borrar memoria sin perder ajustes:** Pulsa **`🧹 Borrar Memoria`** en **Chispa Studio** para reiniciar los recuerdos y logs de partida manteniendo intactos tu altavoz WASAPI, motor de voz, preferencias de reacciones y lore personalizado.

---

## 5. Modos de Reacciones Espontáneas en Tiempo Real

Puedes elegir desde **Chispa Studio** (`⚡ Reacciones en juego`) —con efecto inmediato en partida— entre tres perfiles:

1. **`Tácticas` (Predeterminado recomendado):** Reacciona de forma concisa con *cooldowns* inteligentes solo ante hechos clave: salud crítica (`<= 28 %` en combate), escalada NCPD / llegada de **MaxTac (5★)**, escaneo Kiroshi de **jefes o ciberpsicópatas**, inicio y fin de tiroteos largos, entrada estable en un nuevo distrito y avances en tu misión activa.
2. **`Compañero Activo`:** Suma todo lo anterior más comentarios agudos al cerrar un **pincho (*Shard*)** recién leído y breves apuntes ambientales durante trayectos largos o patrullas en Night City.
3. **`Desactivadas`:** C.H.I.S.P.A. permanece 100 % en silencio salvo cuando pulses **`[Y]`** o **`[U]`**.

---

## 6. Permiso Explícito para Consulta Online a Cyberpunk Wiki (**Desactivada por defecto**)

Por diseño de privacidad y estabilidad, **C.H.I.S.P.A. v2.0 funciona 100 % offline por defecto** (`enable_online_wiki = false`) y **no realiza ninguna conexión a Internet** salvo que tú le des permiso explícito.

Si en algún momento quieres que C.H.I.S.P.A. pueda consultar resúmenes públicos de la *Cyberpunk Wiki (Fandom)* cuando te atasques en un puzle o encargo muy concreto (guardándolos en caché local SQLite de 7 días), tienes **dos formas equivalentes de autorizarlo**:

### Opción A — Desde la interfaz gráfica (Recomendada)
1. Abre **`probar_chispa_es.bat`** (**Chispa Studio**).
2. Marca la casilla **`🌐 Permitir consulta online a Cyberpunk Wiki (Desactivado por defecto)`**.
3. El cambio se guarda al instante y aplica automáticamente aunque ya tengas **`iniciar_servicio_chispa.bat`** abierto. Puedes desmarcarla en cualquier momento para volver a modo 100 % offline.

### Opción B — Editando el archivo de configuración manualmente
1. Abre con un editor de texto:  
   `%USERPROFILE%\.chispa_ai_bridge\companion_prefs.json`
2. Cambia `"enable_online_wiki": false` por **`"enable_online_wiki": true`**:
   ```json
   {
     "enable_online_wiki": true,
     "spontaneous_mode": "tactical",
     "reply_length": "balanced",
     "ambient_cooldown_s": 165.0
   }
   ```
3. Guarda el archivo; el demonio en vivo detectará la modificación automáticamente sin reiniciar la partida.

---

## 7. Pack Opcional de Voz Femenina (Adicional)

Por defecto, **C.H.I.S.P.A. v2.0** incluye la nueva voz masculina de sargento chusquero veterano.

Si prefieres jugar con voz femenina manteniendo todas las mejoras de la `v2.0`, tienes disponible el paquete adicional **`Chispa_LocalAI_FemaleVoicePack_ES_v2.0.0.zip`**:
1. Extrae su contenido sobre tu carpeta raíz (o copia la subcarpeta `models/` dentro de `sparky_local_service/`) para añadir `models/chispa_ref_fem_es.wav` y `models/voice_override.json`.
2. Reinicia el servicio local; tanto `F5-Spanish` como las respuestas de C.H.I.S.P.A. cambiarán automáticamente a la voz femenina diseñada para español.
3. Para volver en cualquier momento a la voz masculina por defecto, ejecuta **`desactivar_parche_voz_femenina.bat`** dentro de `sparky_local_service\`.
