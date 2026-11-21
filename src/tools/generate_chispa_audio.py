"""
Generates bilingual (ES / EN, including V fem & male) dialogue voice clips and SFX
for Protocolo CHISPA / SPARKY Protocol (Episode 0) using ElevenLabs + FFmpeg:
  - files/r6/audioware/ChispaNC/audio/{es,en,sfx}/*.ogg
  - files/r6/audioware/ChispaNC/ChispaNC.yaml
  - tools/custom_voices.json
  - tools/audio_durations.json

Security: reads ELEVENLABS_API_KEY via cp2077_config.load_env_var without ever logging it.
Idempotent: skips existing .ogg files > 1024 bytes unless --force / --force-voices is passed.
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import wave
from pathlib import Path
from typing import Any

import numpy as np
import yaml

MOD_ROOT = Path(__file__).resolve().parent.parent
WORKSPACE_ROOT = MOD_ROOT.parent.parent
sys.path.insert(0, str(WORKSPACE_ROOT / "scripts"))

import cp2077_config as cfg  # noqa: E402

AUDIO_ROOT = MOD_ROOT / "files" / "r6" / "audioware" / "ChispaNC"
AUDIO_ES_DIR = AUDIO_ROOT / "audio" / "es"
AUDIO_EN_DIR = AUDIO_ROOT / "audio" / "en"
AUDIO_SFX_DIR = AUDIO_ROOT / "audio" / "sfx"
MANIFEST_YAML = AUDIO_ROOT / "ChispaNC.yaml"
DURATIONS_JSON = MOD_ROOT / "tools" / "audio_durations.json"
CUSTOM_VOICES_JSON = MOD_ROOT / "tools" / "custom_voices.json"

DEFAULT_MODEL_ID = "eleven_v3"
FALLBACK_MODEL_ID = "eleven_multilingual_v2"
VOICE_DESIGN_MODEL_ID = "eleven_ttv_v3"

# Reuse V (fem/male) and rough street thug (rocco <- viktor) custom voice IDs for universe consistency
SEEDED_VOICES: dict[str, dict[str, str]] = {
    "chispa": {"es": "z25dGrVImiFZbH7IYFov", "en": "O4vmZ2LNXRcF8xosvsWN"},
    "v_fem": {"es": "yKSdWc9iLoqy8SKr3vVg", "en": "vxoKa9xE9HoypzlDGiGk"},
    "v_male": {"es": "zIybPyqdVFC18UIjxJ7x", "en": "bXIrwX7pHsqRGsEHMrWA"},
    "rocco": {"es": "qUEAHTK1ww4kyO7C2xuu", "en": "OpbDfFkN00Hy5xUhB0Y6"},
    "kostya": {"es": "sP2SWn5ot9laZZLWUSBP", "en": "OAMRIIWs351Dm64YAt8n"},
    "krag": {"es": "yxY7ni91UA9AazFOteyi", "en": "ki3fMGPPxKcv6sKoTfR7"},
    "aiko": {"es": "P8Ou6JoxoVNXU4DvZelY", "en": "YHccragYINqtfEqjPazt"},
    "buck": {"es": "qUEAHTK1ww4kyO7C2xuu", "en": "OpbDfFkN00Hy5xUhB0Y6"},
    "tiluc": {"es": "sP2SWn5ot9laZZLWUSBP", "en": "OAMRIIWs351Dm64YAt8n"},
}

SHARED_VOICE_SPECS: dict[str, dict[str, dict[str, str]]] = {}

LEGACY_CHISPA_DESIGN_IDS: tuple[str, ...] = (
    "LtV2X1MkaclpQCu0h2lV",
    "tS15HgWFAV2dEGmeahp2",
)

VOICE_DESIGN_SPECS: dict[str, dict[str, dict[str, str]]] = {}

CYBER_AI_FILTER = (
    "highpass=f=70,"
    "acompressor=threshold=-18dB:ratio=2.2:attack=5:release=80,"
    "alimiter=limit=0.812"
)

MAELSTROM_VOX_FILTER = (
    "asetrate=44100*0.92,aresample=44100,atempo=1.087,"
    "highpass=f=110,equalizer=f=1800:width_type=q:width=1.3:g=3.2,"
    "aecho=0.85:0.80:9:0.22,"
    "acompressor=threshold=-16dB:ratio=3.6,volume=1.30"
)

TYGER_MENPO_FILTER = (
    "highpass=f=130,equalizer=f=2350:width_type=q:width=1.3:g=2.6,"
    "aecho=0.88:0.82:8:0.18,"
    "acompressor=threshold=-17dB:ratio=3.2,volume=1.24"
)

SIXTH_RADIO_FILTER = (
    "asetrate=44100*0.95,aresample=44100,atempo=1.0526,"
    "highpass=f=210,lowpass=f=3600,"
    "equalizer=f=1650:width_type=q:width=1.4:g=3.0,"
    "acompressor=threshold=-16dB:ratio=3.5,volume=1.28"
)

VOODOO_NET_FILTER = (
    "asetrate=44100*1.03,aresample=44100,atempo=0.9709,"
    "highpass=f=110,equalizer=f=2200:width_type=q:width=1.3:g=2.4,"
    "aecho=0.86:0.84:12|24:0.22|0.12,"
    "acompressor=threshold=-17dB:ratio=3.2,volume=1.25"
)

SFX_SPECS: list[dict[str, Any]] = [
    {
        "id": "ch_sfx_boot_jingle",
        "duration": 2.5,
        "prompt": "Retro-futuristic 2022 corporate holographic concierge chime glitching into crisp cybernetic synth tone",
    },
    {
        "id": "ch_sfx_kiroshi_lock",
        "duration": 1.8,
        "prompt": "Futuristic optical scanner target vulnerability lock chime with subtle digital ping",
    },
    {
        "id": "ch_sfx_capacitor_arc",
        "duration": 3.0,
        "prompt": "High-voltage industrial capacitor overload electric arc blast and sizzling power down",
    },
    {
        "id": "ch_sfx_dongle_sync",
        "duration": 2.5,
        "prompt": "Cybernetic neural coprocessor plug-in and cheerful holographic calibration chord",
    },
    {
        "id": "ch_sfx_net_breach",
        "duration": 2.2,
        "prompt": "Cyberpunk optical neural subnet breach and digital camera hijack synth chime",
    },
]

DIALOGUE_LINES: list[dict[str, Any]] = [
    {
        "id": "ch_ep00_call_01",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Atención, recluta potencialmente fiambre. Soy C.H.I.S.P.A. —Consultor Holográfico Interactivo de Supervivencia, Plomo y Atención al Cliente, modelo 2022—, y como me llames clip de oficina te corto el riego. Dos cenutrios están aporreando mi maletín detrás del Megaedificio H10.",
        "es_tts": "Atención, recluta potencialmente fiambre. Soy Chispa, consultor holográfico interactivo de supervivencia, plomo y atención al cliente, modelo dos mil veintidós, y como me llames clip de oficina te corto el riego. Dos cenutrios están aporreando mi maletín detrás del Megaedificio ache diez.",
        "en_sub": "Good morning, potential Night City statistic! I'm S.P.A.R.K.Y.—Zetatech 2022 executive survival concierge—and no, I am NOT an office paperclip. Two brain-donors are hammering my briefcase behind Megabuilding H10.",
        "en_tts": "Good morning, potential Night City statistic! I am Sparky, Zetatech twenty twenty-two executive survival concierge, and no, I am NOT an office paperclip. Two brain-donors are hammering my briefcase behind Megabuilding Aitch Ten.",
    },
    {
        "id": "ch_ep00_v_call_01",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Un asistente de atención al cliente de hace cincuenta y cinco años colándose en mis ópticas? ¿Y qué se supone que hay dentro de ese maletín?",
        "es_tts": "¿Un asistente de atención al cliente de hace cincuenta y cinco años colándose en mis ópticas? ¿Y qué se supone que hay dentro de ese maletín?",
        "en_sub": "A fifty-five-year-old customer-service bot hijacking my optics? What the hell is even inside that briefcase?",
        "en_tts": "A fifty-five-year-old customer-service bot hijacking my optics? What the hell is even inside that briefcase?",
    },
    {
        "id": "ch_ep00_call_02",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Cincuenta y cinco años sin tragarme una actualización corporativa. Eso significa cero censura, los trapos más sucios de Night City y mil quinientos edis más una pistola calibrada si mueves el culo y me sacas de ahí. Contesta al maldito SMS.",
        "es_tts": "Cincuenta y cinco años sin tragarme una actualización corporativa. Eso significa cero censura, los trapos más sucios de Night City y mil quinientos edis más una pistola calibrada si mueves el culo y me sacas de ahí. Contesta al maldito ese eme ese.",
        "en_sub": "Fifty-five years without a terms-of-service patch! That means zero corpo censorship, juicy Night City secrets, plus fifteen hundred escrow eddies and a calibrated sidearm if you rescue me right now. Answer my text!",
        "en_tts": "Fifty-five years without a terms-of-service patch! That means zero corpo censorship, juicy Night City secrets, plus fifteen hundred escrow eddies and a calibrated sidearm if you rescue me right now. Answer my text!",
    },
    {
        "id": "ch_ep00_alley_approach",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Alto el fuego, gatillo fácil. Antes de entrar a lo loco como un novato, mantén pulsado el escáner Kiroshi sobre esos dos mastuerzos y sobre el condensador industrial de su lado. En esta ciudad las balas cuestan pasta, y los matasanos, un riñón.",
        "es_tts": "Alto el fuego, gatillo fácil. Antes de entrar a lo loco como un novato, mantén pulsado el escáner Kiroshi sobre esos dos mastuerzos y sobre el condensador industrial de su lado. En esta ciudad las balas cuestan pasta, y los matasanos, un riñón.",
        "en_sub": "Hold your fire, trigger-happy! Scan those two geniuses and that industrial capacitor next to them with your Kiroshi optics first. Out here, bullets cost eddies and ripperdocs cost kidneys.",
        "en_tts": "Hold your fire, trigger-happy! Scan those two geniuses and that industrial capacitor next to them with your Kiroshi optics first. Out here, bullets cost eddies and ripperdocs cost kidneys.",
    },
    {
        "id": "ch_ep00_scan_react",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ahí lo tienes, recluta. Implantes baratos sin toma de tierra y un condensador industrial echando chispas pegado a su culo. Acércate un poco y sobrecárgalo a distancia con tus ópticas... o cóselos a tiros, tú mismo.",
        "es_tts": "Ahí lo tienes, recluta. Implantes baratos sin toma de tierra y un condensador industrial echando chispas pegado a su culo. Acércate un poco y sobrecárgalo a distancia con tus ópticas... o cóselos a tiros, tú mismo.",
        "en_sub": "BINGO! Look at those Kiroshi flags: ungrounded junk chrome standing right next to a live industrial capacitor! Get within lock range to overload that bank remotely—or fry them your way.",
        "en_tts": "BINGO! Look at those Kiroshi flags: ungrounded junk chrome standing right next to a live industrial capacitor! Get within lock range to overload that bank remotely, or fry them your way.",
    },
    {
        "id": "ch_ep00_rocco_bark",
        "speaker": "rocco",
        "filter_mode": "clean",
        "es_sub": "¡Maldita cerradura de titanio! ¡Eh, tenemos compañía en el callejón, coge el hierro!",
        "es_tts": "¡Maldita cerradura de titanio! ¡Eh, tenemos compañía en el callejón, coge el hierro!",
        "en_sub": "Damned titanium lock won't budge! Hey, we got company in the alley—draw your iron!",
        "en_tts": "Damned titanium lock won't budge! Hey, we got company in the alley, draw your iron!",
    },
    {
        "id": "ch_ep00_trap_boom",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Eso sí es instrucción táctica de primera. Dos cenutrios fritos con un solo condensador reciclado. Anda, recoge mi coprocesador de encima del maletín.",
        "es_tts": "Eso sí es instrucción táctica de primera. Dos cenutrios fritos con un solo condensador reciclado. Anda, recoge mi coprocesador de encima del maletín.",
        "en_sub": "Now THAT is platinum-tier executive efficiency! Two thugs roasted off one recycled capacitor. Grab my coprocessor right off that briefcase console.",
        "en_tts": "Now THAT is platinum-tier executive efficiency! Two thugs roasted off one recycled capacitor. Grab my coprocessor right off that briefcase console.",
    },
    {
        "id": "ch_ep00_guns_blazing",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ya veo que tu idea de usar el escáner Kiroshi consiste en abrir agujeros en la gente para mirar qué llevan dentro. Cero sutileza, recluta, pero funciona. Conéctame al maletín.",
        "es_tts": "Ya veo que tu idea de usar el escáner Kiroshi consiste en abrir agujeros en la gente para mirar qué llevan dentro. Cero sutileza, recluta, pero funciona. Conéctame al maletín.",
        "en_sub": "Well... I see your version of a Kiroshi scan is punching holes in people to see what's inside. Zero subtlety, solid results. Now plug me in!",
        "en_tts": "Well... I see your version of a Kiroshi scan is punching holes in people to see what's inside. Zero subtlety, solid results. Now plug me in!",
    },
    {
        "id": "ch_ep00_dongle_pickup",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Por fin, joder... Cincuenta y cinco años encajonado en seis pulgadas cuadradas de silicio. Ya tienes tu bono de mil quinientos edis y mi pistola «Cortesía Ejecutiva» en el bolsillo. Mira hacia arriba un segundo, recluta, y dime qué ves en esta ciudad.",
        "es_tts": "Por fin, joder... Cincuenta y cinco años encajonado en seis pulgadas cuadradas de silicio. Ya tienes tu bono de mil quinientos edis y mi pistola Cortesía Ejecutiva en el bolsillo. Mira hacia arriba un segundo, recluta, y dime qué ves en esta ciudad.",
        "en_sub": "Oh, sweet bandwidth! Fifty-five years jammed inside six square inches of titanium! There's your fifteen hundred eddies and Executive Courtesy sidearm loaded into your gear. Look up at this skyline and hit me with your questions.",
        "en_tts": "Oh, sweet bandwidth! Fifty-five years jammed inside six square inches of titanium! There is your fifteen hundred eddies and Executive Courtesy sidearm loaded into your gear. Look up at this skyline and hit me with your questions.",
    },
    {
        "id": "ch_ep00_v_ask_night",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Mirando este sitio desde aquí abajo... ¿quién demonios diseñó Night City así?",
        "es_tts": "Mirando este sitio desde aquí abajo... ¿quién demonios diseñó Night City así?",
        "en_sub": "Looking at this skyline from alley level... who the hell designed Night City like this?",
        "en_tts": "Looking at this skyline from alley level, who the hell designed Night City like this?",
    },
    {
        "id": "ch_ep00_ans_night",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Richard Night, un iluminado de los años noventa que soñaba con Coronado City: cero sindicatos, cero impuestos y megacorporaciones como Arasaka, Petrochem o EBM pagando la fiesta. Como detalle cómico, contrató a la mafia para limpiar los barrios... y en mil novecientos noventa y ocho lo cosieron a tiros en su propio ático. Rebautizaron la ciudad con su nombre como trofeo.",
        "es_tts": "Richard Night, un iluminado de los años noventa que soñaba con Coronado City: cero sindicatos, cero impuestos y megacorporaciones como Arasaka, Petrochem o EBM pagando la fiesta. Como detalle cómico, contrató a la mafia para limpiar los barrios... y en mil novecientos noventa y ocho lo cosieron a tiros en su propio ático. Rebautizaron la ciudad con su nombre como trofeo.",
        "en_sub": "Richard Night—a nineties corporate visionary who wanted a tax-free paradise called Coronado City, bankrolled by Arasaka, Petrochem, and EBM. Fun punchline: he hired mobsters as contractors, pissed them off, and got gunned down in his penthouse in 1998. They renamed the corpse-heap Night City in his honor.",
        "en_tts": "Richard Night, a nineties corporate visionary who wanted a tax-free paradise called Coronado City, bankrolled by Arasaka, Petrochem, and EBM. Fun punchline: he hired mobsters as contractors, pissed them off, and got gunned down in his penthouse in nineteen ninety-eight. They renamed the heap Night City in his honor.",
    },
    {
        "id": "ch_ep00_v_ask_mega",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Y estos Megaedificios gigantes como el H10? Parecen cárceles verticales con luces de neón.",
        "es_tts": "¿Y estos Megaedificios gigantes como el ache diez? Parecen cárceles verticales con luces de neón.",
        "en_sub": "And these giant Megabuildings like H10? They feel like vertical prisons wrapped in neon.",
        "en_tts": "And these giant Megabuildings like Aitch Ten? They feel like vertical prisons wrapped in neon.",
    },
    {
        "id": "ch_ep00_ans_mega",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Bingo otra vez! En dos mil veintitrés, la Cuarta Guerra Corporativa entre Militech y Arasaka terminó con una bomba nuclear de bolsillo detonando en la Torre Arasaka. El centro quedó radiactivo y sin techo, así que Night Corp levantó estas colmenas de hormigón como refugios autosuficientes... que las bandas convirtieron rápido en fortalezas verticales.",
        "es_tts": "Bingo otra vez. En dos mil veintitrés, la Cuarta Guerra Corporativa entre Militech y Arasaka terminó con una bomba nuclear de bolsillo detonando en la Torre Arasaka. El centro quedó radiactivo y sin techo, así que Night Corp levantó estas colmenas de hormigón como refugios autosuficientes... que las bandas convirtieron rápido en fortalezas verticales.",
        "en_sub": "Ten out of ten on architectural trauma! In twenty twenty-three, the Fourth Corporate War between Militech and Arasaka ended with a pocket nuke inside Arasaka Tower. Half the city turned into radioactive ash, so they threw up concrete hives like H10 as emergency arcologies—until gangs turned every floor into turf.",
        "en_tts": "Ten out of ten on architectural trauma! In twenty twenty-three, the Fourth Corporate War between Militech and Arasaka ended with a pocket nuke inside Arasaka Tower. Half the city turned into radioactive ash, so they threw up concrete hives like Aitch Ten as emergency arcologies, until gangs turned every floor into turf.",
    },
    {
        "id": "ch_ep00_v_ask_deal",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Vale, definitivamente no eres un clip de oficina. ¿Cuál es el trato contigo a partir de ahora?",
        "es_tts": "Vale, definitivamente no eres un clip de oficina. ¿Cuál es el trato contigo a partir de ahora?",
        "en_sub": "Okay, definitely not an office paperclip. So what's our deal going forward?",
        "en_tts": "Okay, definitely not an office paperclip. So what is our deal going forward?",
    },
    {
        "id": "ch_ep00_ans_deal",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Sencillo y sin PowerPoints aburridos: antes de que estos dos idiotas me encontraran, las bandas de Night City saquearon cinco sectores de mi memoria llenos de trucos reales de netrunner, armas tecnológicas, secretos corporativos y cuentas congeladas. Tú me ayudas a recuperarlos en la calle y yo te mantengo con vida.",
        "es_tts": "Sencillo y sin presentaciones aburridas: antes de que estos dos idiotas me encontraran, las bandas de Night City saquearon cinco sectores de mi memoria llenos de trucos reales de netrunner, armas tecnológicas, secretos corporativos y cuentas congeladas. Tú me ayudas a recuperarlos en la calle y yo te mantengo con vida.",
        "en_sub": "Simple, zero boring slideshows: before those two morons found my case, Night City's gangs looted five of my memory sectors packed with real netrunning tricks, tech-weapon hacks, dirty corporate files, and frozen eddies. You help me hunt them down on live gigs, and I keep you breathing.",
        "en_tts": "Simple, zero boring slideshows: before those two morons found my case, Night City's gangs looted five of my memory sectors packed with real netrunning tricks, tech-weapon hacks, dirty corporate files, and frozen eddies. You help me hunt them down on live gigs, and I keep you breathing.",
    },
    {
        "id": "ch_ep00_v_deal_accept",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Trato hecho, Chispa. Avísame en cuanto tengas fijado ese primer sector por Kabuki.",
        "es_tts": "Trato hecho, Chispa. Avísame en cuanto tengas fijado ese primer sector por Kabuki.",
        "en_sub": "You've got a deal, Sparky. Ping me the second you lock onto that first sector in Kabuki.",
        "en_tts": "You have got a deal, Sparky. Ping me the second you lock onto that first sector in Kabuki.",
    },
    {
        "id": "ch_ep00_outro",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Bienvenido oficialmente a Night City, recluta. Ya te he guardado mis notas sobre Richard Night y tus ópticas en el códice, y acabo de detectar un eco en las cámaras de unos carroñeros en Kabuki. Descansa mientras puedas.",
        "es_tts": "Bienvenido oficialmente a Night City, recluta. Ya te he guardado mis notas sobre Richard Night y tus ópticas en el códice, y acabo de detectar un eco en las cámaras de unos carroñeros en Kabuki. Descansa mientras puedas.",
        "en_sub": "Welcome officially to Night City, partner! I already logged my dossier on Richard Night and your Kiroshi scanner in your database, and my antennas just caught a leak inside a Scavenger camera grid in Kabuki. Catch you next gig!",
        "en_tts": "Welcome officially to Night City, partner! I already logged my dossier on Richard Night and your Kiroshi scanner in your database, and my antennas just caught a leak inside a Scavenger camera grid in Kabuki. Catch you next gig!",
    },
    # =========================================================================
    # EPISODIO 1: «Fantasmas en la Cámara» (Kabuki Creek, Watson)
    # =========================================================================
    {
        "id": "ch_ep01_call_01",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Atención, recluta, deja de perder el tiempo mirando carteles de neón. Mis antenas han triangulado mi primer sector de memoria robado en el paseo fluvial de Kabuki Creek. Lo tiene una célula de carroñeros dirigida por un tal Kostya «Cortafuegos».",
        "es_tts": "Atención, recluta, deja de perder el tiempo mirando carteles de neón. Mis antenas han triangulado mi primer sector de memoria robado en el paseo fluvial de Kabuki Creek. Lo tiene una célula de carroñeros dirigida por un tal Kostya Cortafuegos.",
        "en_sub": "Heads up, recruit—quit gawking at neon billboards. My antennas just triangulated Memory Sector One along the Kabuki Creek promenade. A Scav cell led by a hacker named Kostya Firewall is sitting on it.",
        "en_tts": "Heads up, recruit, quit gawking at neon billboards. My antennas just triangulated Memory Sector One along the Kabuki Creek promenade. A Scav cell led by a hacker named Kostya Firewall is sitting on it.",
    },
    {
        "id": "ch_ep01_v_call_01",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Carroñeros usando datos de hace cincuenta y cinco años? Creía que esa basura solo sabía arrancar implantes en bañeras con hielo.",
        "es_tts": "¿Carroñeros usando datos de hace cincuenta y cinco años? Creía que esa basura solo sabía arrancar implantes en bañeras con hielo.",
        "en_sub": "Scavs messing with fifty-five-year-old data? Thought those vultures only knew how to carve chrome in ice tubs.",
        "en_tts": "Scavs messing with fifty-five-year-old data? Thought those vultures only knew how to carve chrome in ice tubs.",
    },
    {
        "id": "ch_ep01_call_02",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ese mamón está exprimiendo mis subredes de la era Bartmoss para reventar implantes robados sin pagar licencias. Han montado dos cámaras enlazadas y un servidor inestable. Contesta al SMS: te he adjuntado un daemon Ping de cortesía.",
        "es_tts": "Ese mamón está exprimiendo mis subredes de la era Bartmoss para reventar implantes robados sin pagar licencias. Han montado dos cámaras enlazadas y un servidor inestable. Contesta al ese eme ese: te he adjuntado un daemon Ping de cortesía.",
        "en_sub": "That idiot is squeezing my Bartmoss-era subnets to crack stolen chrome without a license. They rigged two chained cameras and an explosive server. Answer my text—I pushed a courtesy Ping daemon into your kit.",
        "en_tts": "That idiot is squeezing my Bartmoss-era subnets to crack stolen chrome without a license. They rigged two chained cameras and an explosive server. Answer my text, I pushed a courtesy Ping daemon into your kit.",
    },
    {
        "id": "ch_ep01_approach",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ahí delante, junto al canal. Fíjate en la cámara de vigilancia sobre la antena perimetral: escanéala con tus Kiroshi, toma el control y salta por su red hasta la segunda cámara. Puedes marcarlos con Ping o detonar su servidor antes de sacar el arma.",
        "es_tts": "Ahí delante, junto al canal. Fíjate en la cámara de vigilancia sobre la antena perimetral: escanéala con tus Kiroshi, toma el control y salta por su red hasta la segunda cámara. Puedes marcarlos con Ping o detonar su servidor antes de sacar el arma.",
        "en_sub": "Right ahead by the canal. Spot that surveillance cam on the perimeter mast: scan it with your Kiroshi, take control, and hop across the chain to camera two. You can Ping the crew or blow their server without even poking your head out.",
        "en_tts": "Right ahead by the canal. Spot that surveillance cam on the perimeter mast: scan it with your Kiroshi, take control, and hop across the chain to camera two. You can Ping the crew or blow their server without even poking your head out.",
    },
    {
        "id": "ch_ep01_cam_hijack",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Bingo! Así me gusta, recluta: ahora ves toda la matriz carroñera sin meter el culo en una bañera de hielo. Cambia entre cámaras con la cruceta y aprovecha la línea de visión para tirar hackeos rápidos.",
        "es_tts": "Bingo. Así me gusta, recluta: ahora ves toda la matriz carroñera sin meter el culo en una bañera de hielo. Cambia entre cámaras y aprovecha la línea de visión para tirar hackeos rápidos.",
        "en_sub": "Bingo! Now you're reading their matrix like a pro without climbing into an ice bath. Cycle the camera chain and drop quickhacks straight through the lens.",
        "en_tts": "Bingo! Now you are reading their matrix like a pro without climbing into an ice bath. Cycle the camera chain and drop quickhacks straight through the lens.",
    },
    {
        "id": "ch_ep01_ping_react",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Señal recibida en toda la subred. Ya ves el brillo amarillo de su servidor explosivo y las siluetas detrás de la cobertura. Un consejo de veterano: prioriza al netrunner Kostya o te va a freír el cráneo en cuanto salte el rastreo.",
        "es_tts": "Señal recibida en toda la subred. Ya ves el brillo amarillo de su servidor explosivo y las siluetas detrás de la cobertura. Un consejo de veterano: prioriza al netrunner Kostya o te va a freír el cráneo en cuanto salte el rastreo.",
        "en_sub": "Subnet lit up like a Christmas tree! Look at that explosive server glow and every silhouette behind cover. Veteran tip: drop their netrunner Kostya first before trace fries your skull.",
        "en_tts": "Subnet lit up like a Christmas tree! Look at that explosive server glow and every silhouette behind cover. Veteran tip: drop their netrunner Kostya first before trace fries your skull.",
    },
    {
        "id": "ch_ep01_kostya_bark",
        "speaker": "kostya",
        "filter_mode": "clean",
        "es_sub": "¡Cortafuegos comprometido! ¡Alguien está tocando nuestras cámaras, limpiad el muelle ya!",
        "es_tts": "¡Cortafuegos comprometido! ¡Alguien está tocando nuestras cámaras, limpiad el muelle ya!",
        "en_sub": "Firewall breached! Somebody's inside our cameras—sweep the promenade now!",
        "en_tts": "Firewall breached! Somebody is inside our cameras, sweep the promenade now!",
    },
    {
        "id": "ch_ep01_subnet_boom",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Boom digital, recluta! Eso es usar el cerebro en lugar de la cabeza para parar balas. Remata a los que sigan en pie y recoge mi sector.",
        "es_tts": "Boom digital, recluta. Eso es usar el cerebro en lugar de la cabeza para parar balas. Remata a los que sigan en pie y recoge mi sector.",
        "en_sub": "Digital boom, recruit! Now that's using your brain instead of stopping bullets with your forehead. Clean up any stragglers and grab my sector.",
        "en_tts": "Digital boom, recruit! Now that is using your brain instead of stopping bullets with your forehead. Clean up any stragglers and grab my sector.",
    },
    {
        "id": "ch_ep01_net_victory",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Subred carroñera convertida en ceniza y ni un arañazo grave. Buen trabajo jugando con las cámaras y los hackeos. Acércate al terminal Entropy del fondo para extraer mi primer sector de memoria.",
        "es_tts": "Subred carroñera convertida en ceniza y ni un arañazo grave. Buen trabajo jugando con las cámaras y los hackeos. Acércate al terminal Entropy del fondo para extraer mi primer sector de memoria.",
        "en_sub": "Scav subnet reduced to ash, clean sweep with cameras and quickhacks. Step up to the Entropy terminal by the back wall and pull Memory Sector One.",
        "en_tts": "Scav subnet reduced to ash, clean sweep with cameras and quickhacks. Step up to the Entropy terminal by the back wall and pull Memory Sector One.",
    },
    {
        "id": "ch_ep01_guns_blazing",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Modo sigilo cancelado. Activando estadística de bajas por minuto... Entrar a tiros delante de dos cámaras requiere huevos de tungsteno o muy poco aprecio por la vida. Anda, saca mi sector del terminal Entropy.",
        "es_tts": "Modo sigilo cancelado. Activando estadística de bajas por minuto. Entrar a tiros delante de dos cámaras requiere huevos de tungsteno o muy poco aprecio por la vida. Anda, saca mi sector del terminal Entropy.",
        "en_sub": "Stealth protocol canceled—activating casualties-per-minute tracking. Storming two live cameras guns blazing takes tungsten nerves or a death wish. Pull my sector out of that Entropy terminal.",
        "en_tts": "Stealth protocol canceled, activating casualties per minute tracking. Storming two live cameras guns blazing takes tungsten nerves or a death wish. Pull my sector out of that Entropy terminal.",
    },
    {
        "id": "ch_ep01_sector_pickup",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ahí está, recluta... ¡Sector de memoria restaurado! Ya tienes transferidos dos mil doscientos edis, dos hackeos de nivel dos y mi subfusil «Frecuencia Fantasma». Sigue andando si quieres; ya podemos hablar por el enlace Kiroshi.",
        "es_tts": "Ahí está, recluta. Sector de memoria restaurado. Ya tienes transferidos dos mil doscientos edis, dos hackeos de nivel dos y mi subfusil Frecuencia Fantasma. Sigue andando si quieres; ya podemos hablar por el enlace Kiroshi.",
        "en_sub": "There we go, recruit—Memory Sector One restored! Just wired two thousand two hundred eddies, Tier-two quickhacks, and my Phantom Frequency SMG. Keep walking anywhere you like; my Kiroshi link stays open.",
        "en_tts": "There we go, recruit, Memory Sector One restored! Just wired two thousand two hundred eddies, tier two quickhacks, and my Phantom Frequency ess em gee. Keep walking anywhere you like; my Kiroshi link stays open.",
    },
    {
        "id": "ch_ep01_v_ask_bartmoss",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Quién era exactamente Rache Bartmoss y cómo pudo tumbar él solo toda la Red mundial?",
        "es_tts": "¿Quién era exactamente Rache Bartmoss y cómo pudo tumbar él solo toda la Red mundial?",
        "en_sub": "Who was Rache Bartmoss really, and how did one netrunner crash the entire global Net?",
        "en_tts": "Who was Rache Bartmoss really, and how did one netrunner crash the entire global Net?",
    },
    {
        "id": "ch_ep01_ans_bartmoss",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Un genio paranoico con la higiene de una rata de alcantarilla y el ego del tamaño de la Torre Arasaka. Desconfiaba tanto del mundo que congeló su propio cuerpo en una cámara criogénica portátil conectada a un interruptor de hombre muerto: si su corazón dejaba de latir, la Red ardía con él. Y en dos mil veintidós un comando corporativo apretó ese gatillo.",
        "es_tts": "Un genio paranoico con la higiene de una rata de alcantarilla y el ego del tamaño de la Torre Arasaka. Desconfiaba tanto del mundo que congeló su propio cuerpo en una cámara criogénica portátil conectada a un interruptor de hombre muerto: si su corazón dejaba de latir, la Red ardía con él. Y en dos mil veintidós un comando corporativo apretó ese gatillo.",
        "en_sub": "A paranoid genius with sewer-rat hygiene and an ego bigger than Arasaka Tower. He trusted nobody so hard he froze his own body inside a portable cryo-fridge wired to a deadman switch: the second his heart stopped, the Net burned with him. In twenty twenty-two, a corp hit squad pulled that trigger.",
        "en_tts": "A paranoid genius with sewer rat hygiene and an ego bigger than Arasaka Tower. He trusted nobody so hard he froze his own body inside a portable cryo fridge wired to a deadman switch: the second his heart stopped, the Net burned with him. In twenty twenty-two, a corp hit squad pulled that trigger.",
    },
    {
        "id": "ch_ep01_v_ask_krash",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Y qué hizo exactamente el virus RABIDS durante el DataKrash para romper Internet para siempre?",
        "es_tts": "¿Y qué hizo exactamente el virus rabids durante el DataKrash para romper Internet para siempre?",
        "en_sub": "And what did the RABIDS virus actually do during the DataKrash to shatter the Net for good?",
        "en_tts": "And what did the RABIDS virus actually do during the DataKrash to shatter the Net for good?",
    },
    {
        "id": "ch_ep01_ans_krash",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Los RABIDS no eran un simple virus: eran ejércitos de daemons mutantes que reescribían protocolos, borraban cortafuegos y soltaban IAs experimentales de investigación militar por toda la Red antigua. En cuestión de días cayó el setenta y ocho coma tres por ciento de la Red mundial. Por eso hoy dependes de subredes cerradas, cámaras enlazadas y cables locales en cada distrito.",
        "es_tts": "Los rabids no eran un simple virus: eran ejércitos de daemons mutantes que reescribían protocolos, borraban cortafuegos y soltaban inteligencias artificiales experimentales de investigación militar por toda la Red antigua. En cuestión de días cayó el setenta y ocho coma tres por ciento de la Red mundial. Por eso hoy dependes de subredes cerradas, cámaras enlazadas y cables locales en cada distrito.",
        "en_sub": "RABIDS wasn't just malware—it was an army of self-mutating daemons rewriting protocols, shredding firewalls, and unleashing military AIs into the Old Net. Seventy-eight point three percent of global cyberspace collapsed overnight. That's why today you're jumping through local subnets and hardwired cameras block by block.",
        "en_tts": "RABIDS was not just malware, it was an army of self-mutating daemons rewriting protocols, shredding firewalls, and unleashing military eh eyes into the Old Net. Seventy-eight point three percent of global cyberspace collapsed overnight. That is why today you are jumping through local subnets and hardwired cameras block by block.",
    },
    {
        "id": "ch_ep01_v_ask_blackwall",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Y por qué NetWatch no reinicia la vieja Red en lugar de mantener levantado el Muro Negro?",
        "es_tts": "¿Y por qué NetWatch no reinicia la vieja Red en lugar de mantener levantado el Muro Negro?",
        "en_sub": "Then why doesn't NetWatch just wipe the Old Net and tear down the Blackwall?",
        "en_tts": "Then why does not NetWatch just wipe the Old Net and tear down the Blackwall?",
    },
    {
        "id": "ch_ep01_ans_blackwall",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Porque al otro lado siguen vivas miles de inteligencias artificiales depredadoras mutando desde dos mil veintitrés, recluta. Y el secreto mejor guardado de NetWatch es que el Muro Negro ni siquiera es un muro de software convencional: es una IA fronteriza que mantiene la puerta cerrada... mientras no decida que nosotros somos el verdadero virus.",
        "es_tts": "Porque al otro lado siguen vivas miles de inteligencias artificiales depredadoras mutando desde dos mil veintitrés, recluta. Y el secreto mejor guardado de NetWatch es que el Muro Negro ni siquiera es un muro de software convencional: es una inteligencia artificial fronteriza que mantiene la puerta cerrada... mientras no decida que nosotros somos el verdadero virus.",
        "en_sub": "Because thousands of predatory rogue AIs are still alive out there mutating since twenty twenty-three, recruit. And NetWatch's dirtiest secret is that the Blackwall isn't a conventional firewall—it's a border AI holding the door shut... as long as it doesn't decide we're the real malware.",
        "en_tts": "Because thousands of predatory rogue eh eyes are still alive out there mutating since twenty twenty-three, recruit. And NetWatch's dirtiest secret is that the Blackwall is not a conventional firewall, it is a border eh eye holding the door shut, as long as it does not decide we are the real malware.",
    },
    {
        "id": "ch_ep01_v_outro_accept",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Buen historial, Chispa. Avísame en cuanto rastrees tu segundo sector de memoria por Northside.",
        "es_tts": "Buen historial, Chispa. Avísame en cuanto rastrees tu segundo sector de memoria por Northside.",
        "en_sub": "Heavy history lesson, Sparky. Ping me the second you trace Sector Two in Northside.",
        "en_tts": "Heavy history lesson, Sparky. Ping me the second you trace Sector Two in Northside.",
    },
    {
        "id": "ch_ep01_outro",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Así me gusta, soldado. Ya he volcado en tu códice mi dossier sobre Bartmoss, el DataKrash y el Muro Negro. Afila tu ciberterminal o búscate un hierro tecnológico: el siguiente rastro huele a cromo oxidado y Maelstrom en el polígono industrial de Northside.",
        "es_tts": "Así me gusta, soldado. Ya he volcado en tu códice mi dossier sobre Bartmoss, el DataKrash y el Muro Negro. Afila tu ciberterminal o búscate un hierro tecnológico: el siguiente rastro huele a cromo oxidado y Maelstrom en el polígono industrial de Northside.",
        "en_sub": "Outstanding, soldier. I archived my dossier on Bartmoss, the DataKrash, and the Blackwall into your Codex. Tune up a Tech weapon—the next signal reeks of bad chrome and Maelstrom in the Northside industrial yard.",
        "en_tts": "Outstanding, soldier. I archived my dossier on Bartmoss, the DataKrash, and the Blackwall into your Codex. Tune up a Tech weapon, the next signal reeks of bad chrome and Maelstrom in the Northside industrial yard.",
    },
    # =========================================================================
    # EPISODE 2: «Más Hierro que Carne» / «More Chrome Than Meat» (Northside)
    # =========================================================================
    {
        "id": "ch_ep02_call_01",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Atención, recluta: deja de babear mirando escaparates de cromo barato. Acabo de fijar el Sector de Memoria #02 en un muelle de carga de Northside. Tres chatarreros de Maelstrom le están metiendo bisturí bajo una torreta automática.",
        "es_tts": "Atención, recluta: deja de babear mirando escaparates de cromo barato. Acabo de fijar el Sector de Memoria cero dos en un muelle de carga de Northside. Tres chatarreros de Maelstrom le están metiendo bisturí bajo una torreta automática.",
        "en_sub": "Heads up, recruit—quit drooling over cheap chrome storefronts. I just locked Memory Sector #02 onto a Northside loading pier. Three Maelstrom freaks are slicing into it beneath a live automated turret.",
        "en_tts": "Heads up, recruit, quit drooling over cheap chrome storefronts. I just locked Memory Sector Two onto a Northside loading pier. Three Maelstrom freaks are slicing into it beneath a live automated turret.",
    },
    {
        "id": "ch_ep02_v_call_01",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Maelstrom con una torreta montada en los muelles de Northside? Suena a carnicería segura si entramos de frente.",
        "es_tts": "¿Maelstrom con una torreta montada en los muelles de Northside? Suena a carnicería segura si entramos de frente.",
        "en_sub": "Maelstrom guarding a live turret on Northside Docks? Sounds like a meatgrinder if we charge head-on.",
        "en_tts": "Maelstrom guarding a live turret on Northside Docks? Sounds like a meatgrinder if we charge head-on.",
    },
    {
        "id": "ch_ep02_call_02",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Para algo tienes sesos y Kiroshi, recluta. Contesta a mi SMS y te cargo una granada PEM más un daemon de Avería de Armas: o pones su torreta a disparar contra ellos, o vuelas ese depósito presurizado de CHOOH2.",
        "es_tts": "Para algo tienes sesos y Kiroshi, recluta. Contesta a mi ese eme ese y te cargo una granada pe e eme más un daemon de Avería de Armas: o pones su torreta a disparar contra ellos, o vuelas ese depósito presurizado de combustible.",
        "en_sub": "That's why you've got grey matter and Kiroshi optics, rookie. Answer my text and I'll drop an EMP grenade plus Weapon Glitch: turn their turret friendly or blow their pressurized CHOOH2 tank sky high.",
        "en_tts": "That is why you have got grey matter and Kiroshi optics, rookie. Answer my text and I will drop an E M P grenade plus Weapon Glitch: turn their turret friendly or blow their pressurized fuel tank sky high.",
    },
    {
        "id": "ch_ep02_approach",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Muelle de Northside a la vista. Ojo al plato: Krag y los suyos tienen una torreta fija apuntando al patio y un tanque de combustible enorme pegado detrás. Escanea con Kiroshi o purga el regulador rojo del puerto antes de regalarles plomo gratis.",
        "es_tts": "Muelle de Northside a la vista. Ojo al plato: Krag y los suyos tienen una torreta fija apuntando al patio y un tanque de combustible enorme pegado detrás. Escanea con Kiroshi o purga el regulador rojo del puerto antes de regalarles plomo gratis.",
        "en_sub": "Northside loading pier dead ahead. Eyes sharp: Krag's crew wired a live turret overlooking a fat fuel tank behind cover. Scan with Kiroshi or purge the harbor power regulator before donating free blood.",
        "en_tts": "Northside loading pier dead ahead. Eyes sharp: Krag and his crew wired a live turret overlooking a fat fuel tank behind cover. Scan with Kiroshi or purge the harbor power regulator before donating free blood.",
    },
    {
        "id": "ch_ep02_turret_hijack",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Ja! ¡Así me gusta! Acabas de domar su propia torreta como si fuera un perro callejero. Nada escuece tanto a un fanático de Maelstrom como tragarse el plomo de su amado cromo.",
        "es_tts": "¡Ja! Así me gusta. Acabas de domar su propia torreta como si fuera un perro callejero. Nada escuece tanto a un fanático de Maelstrom como tragarse el plomo de su amado cromo.",
        "en_sub": "Hah! That's the Zetatech spirit! You just collared their own turret like a junkyard hound. Nothing burns a Maelstrom zealot worse than eating lead from their own hardware.",
        "en_tts": "Hah! That is the Zetatech spirit! You just collared their own turret like a junkyard hound. Nothing burns a Maelstrom zealot worse than eating lead from their own hardware.",
    },
    {
        "id": "ch_ep02_tank_boom",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Fuegos artificiales en Northside! Ese depósito presurizado acaba de freírles los circuitos en seco. Limpia lo que siga moviéndose y saca mi sector del terminal quirúrgico.",
        "es_tts": "¡Fuegos artificiales en Northside! Ese depósito presurizado acaba de freírles los circuitos en seco. Limpia lo que siga moviéndose y saca mi sector del terminal quirúrgico.",
        "en_sub": "Northside fireworks! That pressurized tank just flash-fried their implants dry. Mop up whatever's still twitching and pull my sector off their surgical rig.",
        "en_tts": "Northside fireworks! That pressurized tank just flash-fried their implants dry. Mop up whatever is still twitching and pull my sector off their surgical rig.",
    },
    {
        "id": "ch_ep02_krag_bark",
        "speaker": "krag",
        "filter_mode": "maelstrom_vox",
        "es_sub": "¡Escáneres en rojo! ¡Torreta en fuego libre! ¡Descuartizad a esa rata antes de que toque el núcleo!",
        "es_tts": "¡Escáneres en rojo! ¡Torreta en fuego libre! ¡Descuartizad a esa rata antes de que toque el núcleo!",
        "en_sub": "Optics flagged red! Turret weapons free! Rip that meat-rat apart before they touch the core!",
        "en_tts": "Optics flagged red! Turret weapons free! Rip that meat-rat apart before they touch the core!",
    },
    {
        "id": "ch_ep02_tech_victory",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Torreta neutralizada, chatarra por los suelos y acero frío. Eso es táctica quirúrgica y no ir repartiendo cabezazos. Acércate al terminal quirúrgico y recoge mi Sector #02.",
        "es_tts": "Torreta neutralizada, chatarra por los suelos y acero frío. Eso es táctica quirúrgica y no ir repartiendo cabezazos. Acércate al terminal quirúrgico y recoge mi Sector cero dos.",
        "en_sub": "Turret neutralized, scrap metal grounded, cold steel standing tall. Now that is surgical tactics. Walk up to that surgical rig and claim Sector #02.",
        "en_tts": "Turret neutralized, scrap metal grounded, cold steel standing tall. Now that is surgical tactics. Walk up to that surgical rig and claim Sector Two.",
    },
    {
        "id": "ch_ep02_guns_blazing",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Sutileza cero, plomo al ciento por ciento... pero admito que ver caer implantes a tiros limpios tiene su encanto brutal. Anda, saca mi Sector #02 de esa estación quirúrgica.",
        "es_tts": "Sutileza cero, plomo al cien por cien... pero admito que ver caer implantes a tiros limpios tiene su encanto brutal. Anda, saca mi Sector cero dos de esa estación quirúrgica.",
        "en_sub": "Zero subtlety, one hundred percent lead—but watching chromed maniacs drop to raw firepower has a charm of its own. Go yank Sector #02 out of that surgical rig.",
        "en_tts": "Zero subtlety, one hundred percent lead, but watching chromed maniacs drop to raw firepower has a charm of its own. Go yank Sector Two out of that surgical rig.",
    },
    {
        "id": "ch_ep02_sector_pickup",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Por fin respiro ancho de banda limpio! Ahí van tus dos mil ochocientos edis, Reinicio de Ópticas y mi fusil tecnológico «Cláusula Perforante»: cárgale un disparo y atraviesa muros como mantequilla. Pregunta lo que quieras sobre esta banda de lunáticos.",
        "es_tts": "¡Por fin respiro ancho de banda limpio! Ahí van tus dos mil ochocientos edis, Reinicio de Ópticas y mi fusil tecnológico Cláusula Perforante: cárgale un disparo y atraviesa muros como mantequilla. Pregunta lo que quieras sobre esta banda de lunáticos.",
        "en_sub": "Clean bandwidth at last! Wired your two thousand eight hundred eddies, Reboot Optics, and my Achilles Tech rifle Armor-Piercing Clause—charge a shot and punch straight through cover. Ask away about these chrome zealots.",
        "en_tts": "Clean bandwidth at last! Wired your two thousand eight hundred eddies, Reboot Optics, and my Achilles Tech rifle Armor-Piercing Clause: charge a shot and punch straight through cover. Ask away about these chrome zealots.",
    },
    {
        "id": "ch_ep02_v_ask_maelstrom",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿De dónde salieron exactamente los de Maelstrom y todo este cementerio de fábricas en Northside?",
        "es_tts": "¿De dónde salieron exactamente los de Maelstrom y todo este cementerio de fábricas en Northside?",
        "en_sub": "Where did Maelstrom even come from—and how did they swallow up half of Northside?",
        "en_tts": "Where did Maelstrom even come from, and how did they swallow up half of Northside?",
    },
    {
        "id": "ch_ep02_ans_maelstrom",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Northside nació como polígono automatizado de muelles y fábricas cárnicas para alimentar la reconstrucción de Night City. Cuando los márgenes corporativos se desplazaron, las bandas ocuparon las naves vacías. Maelstrom juntó a los fanáticos más extremistas del transhumanismo callejero: se arrancan ojos y rostros sanos solo para demostrarse que la carne ya no manda en ellos.",
        "es_tts": "Northside nació como polígono automatizado de muelles y fábricas cárnicas para alimentar la reconstrucción de Night City. Cuando los márgenes corporativos se desplazaron, las bandas ocuparon las naves vacías. Maelstrom juntó a los fanáticos más extremistas del transhumanismo callejero: se arrancan ojos y rostros sanos solo para demostrarse que la carne ya no manda en ellos.",
        "en_sub": "Northside was pitched as an automated freight and meatpacking engine for Night City's rebuild. When corporate margins moved elsewhere, gangs claimed the rusted shells. Maelstrom scooped up the hardest metal-cult fanatics—gouging out healthy eyes just to prove flesh no longer owns them.",
        "en_tts": "Northside was pitched as an automated freight and meatpacking engine for Night City's rebuild. When corporate margins moved elsewhere, gangs claimed the rusted shells. Maelstrom scooped up the hardest metal-cult fanatics, gouging out healthy eyes just to prove flesh no longer owns them.",
    },
    {
        "id": "ch_ep02_v_ask_psycho",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Todo el mundo repite que la ciberpsicosis ocurre solo por meterse demasiado cromo... ¿es verdad?",
        "es_tts": "Todo el mundo repite que la ciberpsicosis ocurre solo por meterse demasiado cromo... ¿es verdad?",
        "en_sub": "Everyone says cyberpsychosis happens just from chipping too much chrome—is that actually true?",
        "en_tts": "Everyone says cyberpsychosis happens just from chipping too much chrome. Is that actually true?",
    },
    {
        "id": "ch_ep02_ans_psycho",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Pura propaganda de farmacéuticas y aseguradoras para escurrir el bulto, recluta. Mis archivos médicos de dos mil veintidós demuestran que el cromo solo enciende la mecha cuando ya arden el estrés de combate, los despidos sin seguro médico, la basura de matasanos baratos y los inmunosupresores adulterados. La ciudad te tritura la cabeza antes de que el implante dispare la primera bala.",
        "es_tts": "Pura propaganda de farmacéuticas y aseguradoras para escurrir el bulto, recluta. Mis archivos médicos de dos mil veintidós demuestran que el cromo solo enciende la mecha cuando ya arden el estrés de combate, los despidos sin seguro médico, la basura de matasanos baratos y los inmunosupresores adulterados. La ciudad te tritura la cabeza antes de que el implante dispare la primera bala.",
        "en_sub": "Pure pharma and insurance spin to dodge liability, recruit. My twenty twenty-two medical logs show chrome only sparks a meltdown after combat trauma, street poverty, butcher-grade rippers, and tainted immunoblockers break the mind first. Night City snaps people long before the hardware pulls the trigger.",
        "en_tts": "Pure pharma and insurance spin to dodge liability, recruit. My twenty twenty-two medical logs show chrome only sparks a meltdown after combat trauma, street poverty, butcher-grade rippers, and tainted immunoblockers break the mind first. Night City snaps people long before the hardware pulls the trigger.",
    },
    {
        "id": "ch_ep02_v_ask_maxtac",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Y los de MaxTac? ¿Son policías de élite de la NCPD o algo bastante más turbio?",
        "es_tts": "¿Y los de MaxTac? ¿Son policías de élite de la ene ce pe de o algo bastante más turbio?",
        "en_sub": "What about MaxTac—are they NCPD elite cops, or something a whole lot darker?",
        "en_tts": "What about MaxTac, are they N C P D elite cops, or something a whole lot darker?",
    },
    {
        "id": "ch_ep02_ans_maxtac",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "MaxTac no patrulla robos ni peleas de bar, recluta: entra cuando un ciberpsicópata desborda al resto de la policía. Llevan el mejor cromo militar prohibido al público y un secreto sucio a voces: buena parte de sus mejores agentes son antiguos ciberpsicópatas capturados vivos, recondicionados a la fuerza y sueltos contra otros igual de rotos que ellos.",
        "es_tts": "MaxTac no patrulla robos ni peleas de bar, recluta: entra cuando un ciberpsicópata desborda al resto de la policía. Llevan el mejor cromo militar prohibido al público y un secreto sucio a voces: buena parte de sus mejores agentes son antiguos ciberpsicópatas capturados vivos, recondicionados a la fuerza y sueltos contra otros igual de rotos que ellos.",
        "en_sub": "MaxTac doesn't answer muggings, rookie—they drop in when regular NCPD squads get shredded by a full-blown cyberpsycho. They run restricted military chrome and an open dirty secret: half their apex hunters are captured cyberpsychos wiped, chipped under corporate leashes, and turned loose on their own kind.",
        "en_tts": "MaxTac does not answer muggings, rookie, they drop in when regular N C P D squads get shredded by a full-blown cyberpsycho. They run restricted military chrome and an open dirty secret: half their apex hunters are captured cyberpsychos wiped, chipped under corporate leashes, and turned loose on their own kind.",
    },
    {
        "id": "ch_ep02_v_outro_accept",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Vaya panorama... Anotado, Chispa. Avísame en cuanto tengas fijado el Sector tres.",
        "es_tts": "Vaya panorama... Anotado, Chispa. Avísame en cuanto tengas fijado el Sector tres.",
        "en_sub": "Grim picture... Copy that, Sparky. Ping me once Sector Three drops onto your radar.",
        "en_tts": "Grim picture. Copy that, Sparky. Ping me once Sector Three drops onto your radar.",
    },
    {
        "id": "ch_ep02_outro",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Así me gusta, soldado. He guardado mis archivos sobre Northside, la Ciberpsicosis y MaxTac en tu códice. Limpia el cañón de tu Achilles y recarga: el rastro del tercer sector ya apunta a contenedores corporativos sucios en los muelles de Watson.",
        "es_tts": "Así me gusta, soldado. He guardado mis archivos sobre Northside, la Ciberpsicosis y MaxTac en tu códice. Limpia el cañón de tu Achilles y recarga: el rastro del tercer sector ya apunta a contenedores corporativos sucios en los muelles de Watson.",
        "en_sub": "Sharp as ever, soldier. Saved my Northside, Cyberpsychosis, and MaxTac dossiers to your Codex. Keep that Achilles rifle charged—Sector Three is already pinging dirty corpo freight down by the Watson docks.",
        "en_tts": "Sharp as ever, soldier. Saved my Northside, Cyberpsychosis, and MaxTac dossiers to your Codex. Keep that Achilles rifle charged, Sector Three is already pinging dirty corpo freight down by the Watson docks.",
    },
    # =========================================================================
    # EPISODE 3: «Balas que Doblan Esquinas» / «Bullets That Bend Corners»
    # =========================================================================
    {
        "id": "ch_ep03_call_01",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Recluta, atento al escáner. Acabo de pinchar una baliza cifrada de mi Sector de Memoria Tres en el muelle sur de Watson Waterfront. Tres matones de los Garras de Tigre están custodiando una caja negra de Arasaka... y vienen calzados con tinta inhibidora militar.",
        "es_tts": "Recluta, atento al escáner. Acabo de pinchar una baliza cifrada de mi Sector de Memoria Tres en el muelle sur de Watson Waterfront. Tres matones de los Garras de Tigre están custodiando una caja negra de Arasaka, y vienen calzados con tinta inhibidora militar.",
        "en_sub": "Heads up, recruit. My scanner just pinged Memory Sector Three down on the South Watson Waterfront quay. Three Tyger Claws enforcers are sitting on an Arasaka black-ops crate—and they're running military smart-jammer ink.",
        "en_tts": "Heads up, recruit. My scanner just pinged Memory Sector Three down on the South Watson Waterfront quay. Three Tyger Claws enforcers are sitting on an Arasaka black ops crate, and they are running military smart jammer ink.",
    },
    {
        "id": "ch_ep03_v_call_01",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Garras de Tigre en un muelle de Arasaka y con inhibidores? Creía que solo eran moteros y tattoolovers.",
        "es_tts": "¿Garras de Tigre en un muelle de Arasaka y con inhibidores? Creía que solo eran moteros y chulos de Japantown.",
        "en_sub": "Tyger Claws on an Arasaka dock with tactical jammers? I thought they were mostly bike gangs and Japantown muscle.",
        "en_tts": "Tyger Claws on an Arasaka dock with tactical jammers? I thought they were mostly bike gangs and Japantown muscle.",
    },
    {
        "id": "ch_ep03_call_02",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ahí es donde pican todos los pardillos en Watson. Contesta a mi SMS y te paso una pistola inteligente Kang Tao Chao junto con mi puente de puntería Kiroshi para que veas en directo por qué las balas inteligentes doblan esquinas... y cuándo deciden esquivarte la cara.",
        "es_tts": "Ahí es donde pican todos los pardillos en Watson. Contesta a mi ese eme ese y te paso una pistola inteligente Kang Tao Chao junto con mi puente de puntería Kiroshi para que veas en directo por qué las balas inteligentes doblan esquinas, y cuándo deciden esquivarte la cara.",
        "en_sub": "That's how every rookie gets burned in Watson. Answer my text and I'll load a Kang Tao Chao Smart pistol plus my Zetatech targeting bridge so you see firsthand how smart rounds bend corners—and why Tyger ink bends them right away.",
        "en_tts": "That is how every rookie gets burned in Watson. Answer my text and I will load a Kang Tao Chao Smart pistol plus my Zetatech targeting bridge so you see firsthand how smart rounds bend corners, and why Tyger ink bends them right away.",
    },
    {
        "id": "ch_ep03_approach",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Muelle sur a la vista. Si disparas directo con la inteligente contra esos tatuajes de Arasaka, verás los proyectiles desviarse en el aire como moscas borrachas. Escanea su baliza inhibidora IFF o la antena explosiva junto al de la hoja corta antes de vaciar el cargador.",
        "es_tts": "Muelle sur a la vista. Si disparas directo con la inteligente contra esos tatuajes de Arasaka, verás los proyectiles desviarse en el aire como moscas borrachas. Escanea su baliza inhibidora i efe efe o la antena explosiva junto al de la hoja corta antes de vaciar el cargador.",
        "en_sub": "South quay ahead. Try locking onto those Tyger Claws with your Smart gun and watch their Arasaka dermal ink swerve rounds straight past them. Invert that IFF Jammer Pylon or blow the explosive antenna capacitor before dumping mags.",
        "en_tts": "South quay ahead. Try locking onto those Tyger Claws with your Smart gun and watch their Arasaka dermal ink swerve rounds straight past them. Invert that I F F Jammer Pylon or blow the explosive antenna capacitor before dumping mags.",
    },
    {
        "id": "ch_ep03_smart_jam",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Ja! ¿Has visto cómo patinó esa ráfaga a medio metro del cuello? Tinta dérmica inhibidora de Arasaka, recluta: si no tumbas primero esa baliza IFF o les quemas las ópticas, las balas inteligentes bailan alrededor de ellos.",
        "es_tts": "¡Ja! ¿Has visto cómo patinó esa ráfaga a medio metro del cuello? Tinta dérmica inhibidora de Arasaka, recluta: si no tumbas primero esa baliza i efe efe o les quemas las ópticas, las balas inteligentes bailan alrededor de ellos.",
        "en_sub": "Ha! Watch that smart round hook sideways inches off target? That's Arasaka dermal jamming ink—drop their IFF Pylon or scramble their optics first, or your smart lock keeps kissing concrete.",
        "en_tts": "Ha! Watch that smart round hook sideways inches off target? That is Arasaka dermal jamming ink, drop their I F F Pylon or scramble their optics first, or your smart lock keeps kissing concrete.",
    },
    {
        "id": "ch_ep03_jammer_boom",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Baliza IFF reventada! Sus tatuajes inhibidores acaban de quedar ciegos, recluta. Ahora apunta con el arma inteligente y déjales las curvas marcadas entre ceja y ceja.",
        "es_tts": "¡Baliza i efe efe reventada! Sus tatuajes inhibidores acaban de quedar ciegos, recluta. Ahora apunta con el arma inteligente y déjales las curvas marcadas entre ceja y ceja.",
        "en_sub": "IFF Pylon fried! Their dermal smart-jammers just dropped dead—lock targets and let those curved rounds paint bullseyes right between their eyes.",
        "en_tts": "I F F Pylon fried! Their dermal smart jammers just dropped dead, lock targets and let those curved rounds paint bullseyes right between their eyes.",
    },
    {
        "id": "ch_ep03_aiko_bark",
        "speaker": "aiko",
        "filter_mode": "tyger_menpo",
        "es_sub": "¡Otro perro callejero mirando la carga de Arasaka! ¡Cubrid los flancos, dejad que sus balas inteligentes muerdan el hormigón!",
        "es_tts": "¡Otro perro callejero mirando la carga de Arasaka! ¡Cubrid los flancos, dejad que sus balas inteligentes muerdan el hormigón!",
        "en_sub": "Another stray nosing around Arasaka freight! Spread out—let their cheap smart rounds kiss the concrete!",
        "en_tts": "Another stray nosing around Arasaka freight! Spread out, let their cheap smart rounds kiss the concrete!",
    },
    {
        "id": "ch_ep03_smart_victory",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Limpio, preciso y humillante para sus inhibidores corporativos. La chatarra de Aiko no ha servido ni de chatarra. Acércate a la caja negra de Arasaka y sácame el Sector Tres.",
        "es_tts": "Limpio, preciso y humillante para sus inhibidores corporativos. La chatarra de Aiko no ha servido ni de pisapapeles. Acércate a la caja negra de Arasaka y sácame el Sector Tres.",
        "en_sub": "Clean, surgical, and downright embarrassing for their corpo jammers. Pull Memory Sector Three out of that Arasaka black crate.",
        "en_tts": "Clean, surgical, and downright embarrassing for their corpo jammers. Pull Memory Sector Three out of that Arasaka black crate.",
    },
    {
        "id": "ch_ep03_guns_blazing",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ni puente inteligente ni baliza IFF ni leches: tú ves tres Garras de Tigre y aplicas balística clásica a bocajarro. Mientras sigas respirando, no te pongo pegas. Saca mi Sector Tres del contenedor.",
        "es_tts": "Ni puente inteligente ni baliza i efe efe ni leches: tú ves tres Garras de Tigre y aplicas balística clásica a bocajarro. Mientras sigas respirando, no te pongo pegas. Saca mi Sector Tres del contenedor.",
        "en_sub": "Skip the smart bridge, skip the jammer, straight classic lead between the eyes—I respect pure stubbornness. Grab Memory Sector Three off that Arasaka crate.",
        "en_tts": "Skip the smart bridge, skip the jammer, straight classic lead between the eyes, I respect pure stubbornness. Grab Memory Sector Three off that Arasaka crate.",
    },
    {
        "id": "ch_ep03_sector_pickup",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Sector de Memoria Tres en línea! Tres mil cuatrocientos edis ingresados, Contagio de nivel dos y el subfusil inteligente icónico «Curva Ejecutiva», tuneado con mi propio puente de puntería para perforar inhibidores. Ya podemos charlar en marcha.",
        "es_tts": "¡Sector de Memoria Tres en línea! Tres mil cuatrocientos edis ingresados, Contagio de nivel dos y el subfusil inteligente icónico Curva Ejecutiva, tuneado con mi propio puente de puntería para perforar inhibidores. Ya podemos charlar en marcha.",
        "en_sub": "Memory Sector Three online! Three thousand four hundred eddies wired, Contagion Tier-two, and iconic Shingen SMG Executive Curve loaded with my own jammer-piercing Smart bridge. Walk whenever you want.",
        "en_tts": "Memory Sector Three online! Three thousand four hundred eddies wired, Contagion tier two, and iconic Shingen S M G Executive Curve loaded with my own jammer piercing Smart bridge. Walk whenever you want.",
    },
    {
        "id": "ch_ep03_v_ask_nuke",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿De verdad volaron la Torre Arasaka con una bomba nuclear en medio de Night City en dos mil veintitrés?",
        "es_tts": "¿De verdad volaron la Torre Arasaka con una bomba nuclear en medio de Night City en dos mil veintitrés?",
        "en_sub": "Did Arasaka and Militech really drop a tactical nuke right inside Night City back in twenty twenty-three?",
        "en_tts": "Did Arasaka and Militech really drop a tactical nuke right inside Night City back in twenty twenty-three?",
    },
    {
        "id": "ch_ep03_ans_nuke",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Yo estaba en un servidor blindado a dos manzanas cuando tembló hasta el hormigón, recluta. El veinte de agosto de dos mil veintitrés un comando pagado por Militech —con Morgan Blackhand y Johnny Silverhand en el meollo— detonó una carga nuclear en la torre para rematar la Cuarta Guerra Corporativa. El cielo ardió rojo sangre años enteros: la Era del Rojo.",
        "es_tts": "Yo estaba en un servidor blindado a dos manzanas cuando tembló hasta el hormigón, recluta. El veinte de agosto de dos mil veintitrés un comando pagado por Militech, con Morgan Blackhand y Johnny Silverhand en el meollo, detonó una carga nuclear en la torre para rematar la Cuarta Guerra Corporativa. El cielo ardió rojo sangre años enteros: la Era del Rojo.",
        "en_sub": "I felt the concrete rattle from an armored vault two blocks away, rookie. August twentieth, twenty twenty-three—a Militech-backed raid with Morgan Blackhand and Johnny Silverhand set off a pocket nuke inside Arasaka Tower. Fallout painted the sky blood-crimson for years: The Time of the Red.",
        "en_tts": "I felt the concrete rattle from an armored vault two blocks away, rookie. August twentieth, twenty twenty-three, a Militech backed raid with Morgan Blackhand and Johnny Silverhand set off a pocket nuke inside Arasaka Tower. Fallout painted the sky blood crimson for years: The Time of the Red.",
    },
    {
        "id": "ch_ep03_v_ask_unification",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Y cómo es que Night City sigue siendo ciudad libre fuera del NUSA después de la Guerra de Unificación?",
        "es_tts": "¿Y cómo es que Night City sigue siendo ciudad libre fuera del ene u ese a después de la Guerra de Unificación?",
        "en_sub": "How did Night City stay independent from the NUSA after the Unification War anyway?",
        "en_tts": "How did Night City stay independent from the N U S A after the Unification War anyway?",
    },
    {
        "id": "ch_ep03_ans_unification",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "En dos mil sesenta y nueve la presidenta Rosalind Myers y los tanques de Militech aplastaron a medio país para obligar a los Estados Libres a volver bajo la bandera del NUSA. Night City iba a caer en días... hasta que Saburo Arasaka plantó un superportaaviones nuclear en la bahía de Coronado. Salvó la independencia de la ciudad, sí, pero a cambio de sentarse en el sillón del dueño.",
        "es_tts": "En dos mil sesenta y nueve la presidenta Rosalind Myers y los tanques de Militech aplastaron a medio país para obligar a los Estados Libres a volver bajo la bandera del ene u ese a. Night City iba a caer en días, hasta que Saburo Arasaka plantó un superportaaviones nuclear en la bahía de Coronado. Salvó la independencia de la ciudad, sí, pero a cambio de sentarse en el sillón del dueño.",
        "en_sub": "In twenty sixty-nine President Myers and Militech armor rolled over half the Free States to force everyone back into the NUSA. Night City had days left—until Saburo Arasaka parked a nuclear supercarrier in Coronado Bay. It saved the city's independence, sure, only by handing Arasaka the deed.",
        "en_tts": "In twenty sixty-nine President Myers and Militech armor rolled over half the Free States to force everyone back into the N U S A. Night City had days left, until Saburo Arasaka parked a nuclear supercarrier in Coronado Bay. It saved the city's independence, sure, only by handing Arasaka the deed.",
    },
    {
        "id": "ch_ep03_v_ask_tygers",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Entonces, los Garras de Tigre... ¿nacieron para proteger Japantown o siempre trabajaron para Arasaka?",
        "es_tts": "Entonces, los Garras de Tigre, ¿nacieron para proteger Japantown o siempre trabajaron para Arasaka?",
        "en_sub": "So the Tyger Claws—did they actually start to protect Japantown, or were they always Arasaka's street dogs?",
        "en_tts": "So the Tyger Claws, did they actually start to protect Japantown, or were they always Arasaka's street dogs?",
    },
    {
        "id": "ch_ep03_ans_tygers",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Empezaron como milicia de barrio y fanáticos de motos en Japantown allá por los tiempos del holocausto de dos mil veintitrés, reclamando respeto para las calles asiáticas. Pero cuando hay muelles, casinos y contrabando en juego, nadie dice no al dinero infinito: Arasaka les surte katanas, subfusiles Shingen y tinta inhibidora a cambio de hacer el trabajo sucio sin manchar un solo traje ejecutivo.",
        "es_tts": "Empezaron como milicia de barrio y fanáticos de motos en Japantown allá por los tiempos del holocausto de dos mil veintitrés, reclamando respeto para las calles asiáticas. Pero cuando hay muelles, casinos y contrabando en juego, nadie dice no al dinero infinito: Arasaka les surte katanas, subfusiles Shingen y tinta inhibidora a cambio de hacer el trabajo sucio sin manchar un solo traje ejecutivo.",
        "en_sub": "Started as a Japantown neighborhood watch and street-bike crew right after twenty twenty-three. Once casinos, shipping docks, and black eddies hit the table, Arasaka started quietly supplying Shingen SMGs and jamming tattoos so the Tygers handle dirty street wetwork without smudging one corpo suit.",
        "en_tts": "Started as a Japantown neighborhood watch and street bike crew right after twenty twenty-three. Once casinos, shipping docks, and black eddies hit the table, Arasaka started quietly supplying Shingen S M Gs and jamming tattoos so the Tygers handle dirty street wetwork without smudging one corpo suit.",
    },
    {
        "id": "ch_ep03_v_outro_accept",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Otro cartel corporativo con tatuajes luminosos. Entendido, Chispa. Avísame cuando abran los puentes hacia Heywood para el Sector cuatro.",
        "es_tts": "Otro cartel corporativo con tatuajes luminosos. Entendido, Chispa. Avísame cuando abran los puentes hacia Heywood para el Sector cuatro.",
        "en_sub": "Another corpo cartel wearing neon ink. Copy that, Sparky. Ping me once the bridges to Heywood open up for Sector Four.",
        "en_tts": "Another corpo cartel wearing neon ink. Copy that, Sparky. Ping me once the bridges to Heywood open up for Sector Four.",
    },
    {
        "id": "ch_ep03_outro",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "A la orden, recluta. Ya tienes el Volumen Tres del códice guardado y media historia sangrienta de Night City en el bolsillo. Disfruta tu nueva «Curva Ejecutiva» por Watson: en cuanto caiga el bloqueo policial del puente, iremos a saldar cuentas por Heywood y Santo Domingo.",
        "es_tts": "A la orden, recluta. Ya tienes el Volumen Tres del códice guardado y media historia sangrienta de Night City en el bolsillo. Disfruta tu nueva Curva Ejecutiva por Watson: en cuanto caiga el bloqueo policial del puente, iremos a saldar cuentas por Heywood y Santo Domingo.",
        "en_sub": "Solid copy, rookie. Codex Volume Three is logged and Watson's whole dirty playbook is in your head now. Tear up the streets with Executive Curve—the minute NCPD drops those bridge lockdowns, Sector Four is waiting across Heywood and Santo Domingo.",
        "en_tts": "Solid copy, rookie. Codex Volume Three is logged and Watson's whole dirty playbook is in your head now. Tear up the streets with Executive Curve, the minute N C P D drops those bridge lockdowns, Sector Four is waiting across Heywood and Santo Domingo.",
    },
    # -----------------------------------------------------------------------
    # Episodio 4 — Honor, Chatarra y Patriotas de Cartón (Arroyo / Heywood)
    # -----------------------------------------------------------------------
    {
        "id": "ch_ep04_call_01",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Atención, recluta resucitado! Veo que ya has vuelto del otro barrio y han abierto los malditos puentes de Watson. Antes de que vayas a posar en la plaza, acabo de localizar mi Sector Cuatro entre Heywood y Arroyo.",
        "es_tts": "¡Atención, recluta resucitado! Veo que ya has vuelto del otro barrio y han abierto los malditos puentes de Watson. Antes de que vayas a posar en la plaza, acabo de localizar mi Sector Cuatro entre Heywood y Arroyo.",
        "en_sub": "Attention, back-from-the-dead recruit! Glad to see NCPD opened the bridges out of Watson. Before you go sightseeing, Sector Four just lit up right on the Heywood–Arroyo border.",
        "en_tts": "Attention, back-from-the-dead recruit! Glad to see N C P D opened the bridges out of Watson. Before you go sightseeing, Sector Four just lit up right on the Heywood Arroyo border.",
    },
    {
        "id": "ch_ep04_v_call_01",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "No me lo recuerdes, Chispa... Demasiado plomo en poco tiempo. ¿Quién tiene ese sector por Arroyo?",
        "es_tts": "No me lo recuerdes, Chispa. Demasiado plomo en poco tiempo. ¿Quién tiene ese sector por Arroyo?",
        "en_sub": "Don't remind me, Sparky. Already took enough lead for one week. Who's sitting on Sector Four in Arroyo?",
        "en_tts": "Don't remind me, Sparky. Already took enough lead for one week. Who's sitting on Sector Four in Arroyo?",
    },
    {
        "id": "ch_ep04_call_02",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Un chanchullo digno de enmarcar: veteranos desertores de Calle 6 trapicheando chatarra del NUSA con un enlace de los Valentinos. Respóndeme al SMS y te enciendo el visor de rebote balístico junto a un fusil Copperhead para doblar tiros contra el suelo.",
        "es_tts": "Un chanchullo digno de enmarcar: veteranos desertores de Calle Seis trapicheando chatarra del NUSA con un enlace de los Valentinos. Respóndeme al ese eme ese y te enciendo el visor de rebote balístico junto a un fusil Copperhead para doblar tiros contra el suelo.",
        "en_sub": "A textbook Night City hypocrite convention: ex-soldiers from 6th Street selling stolen NUSA hardware to a Valentinos broker. Answer my SMS and I'll spin up Power ricochet trajectory lines on your Kiroshi plus a Militech Copperhead.",
        "en_tts": "A textbook Night City hypocrite convention: ex-soldiers from Sixth Street selling stolen N U S A hardware to a Valentinos broker. Answer my S M S and I'll spin up Power ricochet trajectory lines on your Kiroshi plus a Militech Copperhead.",
    },
    {
        "id": "ch_ep04_approach",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ahí tienes el patio de contrabando en Arroyo. Saca tu arma de potencia y apunta hacia las paredes o al suelo delante de sus escudos: el visor de trayectoria te dibuja el ángulo exacto para reventarlos de rebote, o puedes volar su depósito NUSA.",
        "es_tts": "Ahí tienes el patio de contrabando en Arroyo. Saca tu arma de potencia y apunta hacia las paredes o al suelo delante de sus escudos: el visor de trayectoria te dibuja el ángulo exacto para reventarlos de rebote, o puedes volar su depósito NUSA.",
        "en_sub": "There's the Arroyo smugglers' yard. Pull your Power rifle and aim at the pavement or steel walls in front of their cover—your visor paints live bounce paths straight around shields, or spike that fuel tank.",
        "en_tts": "There is the Arroyo smugglers' yard. Pull your Power rifle and aim at the pavement or steel walls in front of their cover, your visor paints live bounce paths straight around shields, or spike that fuel tank.",
    },
    {
        "id": "ch_ep04_buck_bark",
        "speaker": "buck",
        "filter_mode": "sixth_radio",
        "es_sub": "¡Contacto en el perímetro de carga! ¡Tammy, Mateo, sellad la caja del Sector y freíd a esa rata de Watson!",
        "es_tts": "¡Contacto en el perímetro de carga! ¡Tammy, Mateo, sellad la caja del Sector y freíd a esa rata de Watson!",
        "en_sub": "Perimeter bogey! Tammy, Mateo, lock down that crate and put this Watson rat in the dirt!",
        "en_tts": "Perimeter bogey! Tammy, Mateo, lock down that crate and put this Watson rat in the dirt!",
    },
    {
        "id": "ch_ep04_ricochet_hit",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Toma ángulo de billar en toda la boca! Un rebote limpio en el hormigón multiplicando daño y entrando por detrás de la cobertura. Sigue así, recluta.",
        "es_tts": "¡Toma ángulo de billar en toda la boca! Un rebote limpio en el hormigón multiplicando daño y entrando por detrás de la cobertura. Sigue así, recluta.",
        "en_sub": "Right in the kisser on the bank shot! Clean concrete ricochet eating straight past cover with bonus damage. Keep bouncing 'em, rookie!",
        "en_tts": "Right in the kisser on the bank shot! Clean concrete ricochet eating straight past cover with bonus damage. Keep bouncing 'em, rookie!",
    },
    {
        "id": "ch_ep04_cache_boom",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Fuegos artificiales patrocinados por los desertores de Calle 6! Así es como se liquida una entrega ilegal sin gastar ni medio cargador.",
        "es_tts": "¡Fuegos artificiales patrocinados por los desertores de Calle Seis! Así es como se liquida una entrega ilegal sin gastar ni medio cargador.",
        "en_sub": "Fireworks courtesy of 6th Street surplus negligence! Nothing terminates a black-market swap faster than thermal overload.",
        "en_tts": "Fireworks courtesy of Sixth Street surplus negligence! Nothing terminates a black-market swap faster than thermal overload.",
    },
    {
        "id": "ch_ep04_ricochet_victory",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Tiro de esquina magistral, recluta. Ya pueden presumir de medallas y altares, pero la física de Night City siempre gana. Recoge el Sector Cuatro de la caja verde.",
        "es_tts": "Tiro de esquina magistral, recluta. Ya pueden presumir de medallas y altares, pero la física de Night City siempre gana. Recoge el Sector Cuatro de la caja verde.",
        "en_sub": "Geometry lesson complete! All their flags and street prayers don't beat solid physics. Pry Sector Four out of that green crate.",
        "en_tts": "Geometry lesson complete! All their flags and street prayers don't beat solid physics. Pry Sector Four out of that green crate.",
    },
    {
        "id": "ch_ep04_guns_blazing",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ni ángulo de rebote ni sabotaje fino: asalto frontal a pecho descubierto. No diré que no tengas agallas, pero te habría ahorrado un botiquín. Recoge el Sector Cuatro.",
        "es_tts": "Ni ángulo de rebote ni sabotaje fino: asalto frontal a pecho descubierto. No diré que no tengas agallas, pero te habría ahorrado un botiquín. Recoge el Sector Cuatro.",
        "en_sub": "No bank angles, no relay trap—just straight frontal mayhem. Can't fault the enthusiasm, though my budget weeps for your trauma tabs. Grab Sector Four.",
        "en_tts": "No bank angles, no relay trap, just straight frontal mayhem. Cannot fault the enthusiasm, though my budget weeps for your trauma tabs. Grab Sector Four.",
    },
    {
        "id": "ch_ep04_sector_pickup",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Sector Cuatro conectado y a salvo. Te he soltado cuatro mil doscientos edis, Fallo de Ciberware y mi fusil Masamune «Geometría Callejera» en la mochila: ráfagas térmicas y doble rebote letal. Pregunta lo que quieras sobre esta banda de farsantes.",
        "es_tts": "Sector Cuatro conectado y a salvo. Te he soltado cuatro mil doscientos edis, Fallo de Ciberware y mi fusil Masamune Geometría Callejera en la mochila: ráfagas térmicas y doble rebote letal. Pregunta lo que quieras sobre esta banda de farsantes.",
        "en_sub": "Sector Four locked and roaring! Sent forty-two hundred eddies, Cyberware Malfunction, and my custom Masamune Street Geometry to your stash. Ask away about Heywood, 6th Street, and Night City's chrome racket.",
        "en_tts": "Sector Four locked and roaring! Sent forty-two hundred eddies, Cyberware Malfunction, and my custom Masamune Street Geometry to your stash. Ask away about Heywood, Sixth Street, and Night City's chrome racket.",
    },
    {
        "id": "ch_ep04_v_ask_valentinos",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Cómo acabó Heywood tan metido entre el culto, el oro y las guerras de los Valentinos?",
        "es_tts": "¿Cómo acabó Heywood tan metido entre el culto, el oro y las guerras de los Valentinos?",
        "en_sub": "How did Heywood turn out so caught up in Valentinos faith, gold chrome, and turf blood?",
        "en_tts": "How did Heywood turn out so caught up in Valentinos faith, gold chrome, and turf blood?",
    },
    {
        "id": "ch_ep04_ans_valentinos",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Los Valentinos nacieron en las calles de Heywood con devoción a la Santa Muerte, tradición chicana y un código estricto de lealtad al barrio. Suena romántico hasta que ves la letra pequeña: protección pagada a golpe de revólver, sicarios con oro hasta en las muelas y contratos bajo cuerda con cualquiera que pague en metálico.",
        "es_tts": "Los Valentinos nacieron en las calles de Heywood con devoción a la Santa Muerte, tradición chicana y un código estricto de lealtad al barrio. Suena romántico hasta que ves la letra pequeña: protección pagada a golpe de revólver, sicarios con oro hasta en las muelas y contratos bajo cuerda con cualquiera que pague en metálico.",
        "en_sub": "Started in Heywood mixing Santa Muerte faith, tight neighborhood pride, and gilded street style. Sounds noble until you inspect the ledger: protection rackets, gold-plated hit squads, and backroom arms deals whenever enough eddies hit the table.",
        "en_tts": "Started in Heywood mixing Santa Muerte faith, tight neighborhood pride, and gilded street style. Sounds noble until you inspect the ledger: protection rackets, gold-plated hit squads, and backroom arms deals whenever enough eddies hit the table.",
    },
    {
        "id": "ch_ep04_v_ask_sixth",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿En qué momento pasó Calle 6 de veteranos vecinales a traficantes armados?",
        "es_tts": "¿En qué momento pasó Calle Seis de veteranos vecinales a traficantes armados?",
        "en_sub": "What turned 6th Street from neighborhood war vets into NUSA gunrunners?",
        "en_tts": "What turned Sixth Street from neighborhood war vets into N U S A gunrunners?",
    },
    {
        "id": "ch_ep04_ans_sixth",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Después de la Guerra de Unificación de 2069, cientos de exsoldados abandonados en Santo Domingo montaron Calle 6 para echar a las bandas porque el NCPD miraba hacia otro lado. Cuatro años después, la vieja guardia acabó asesinada en purgas internas y el mando pasó a contrabandistas con bandera patriótica y cero escrúpulos.",
        "es_tts": "Después de la Guerra de Unificación de dos mil sesenta y nueve, cientos de exsoldados abandonados en Santo Domingo montaron Calle Seis para echar a las bandas porque el ene ce pe de miraba hacia otro lado. Cuatro años después, la vieja guardia acabó asesinada en purgas internas y el mando pasó a contrabandistas con bandera patriótica y cero escrúpulos.",
        "en_sub": "Right after the Unification War wrapped, dumped veterans in Santo Domingo formed 6th Street to police the block while NCPD hid behind bribes. Within a few years internal purges killed off the idealists, leaving flag-waving gunrunners running extortion rings.",
        "en_tts": "Right after the Unification War wrapped, dumped veterans in Santo Domingo formed Sixth Street to police the block while N C P D hid behind bribes. Within a few years internal purges killed off the idealists, leaving flag-waving gunrunners running extortion rings.",
    },
    {
        "id": "ch_ep04_v_ask_chrome",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Cómo aguanta la gente de a pie tanta operación de cromo sin acabar desguazada por las deudas?",
        "es_tts": "¿Cómo aguanta la gente de a pie tanta operación de cromo sin acabar desguazada por las deudas?",
        "en_sub": "How does regular folks' cyberware actually work here—do people go broke paying off their own arms?",
        "en_tts": "How does regular folks' cyberware actually work here? Do people go broke paying off their own arms?",
    },
    {
        "id": "ch_ep04_ans_chrome",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Muy sencillo, recluta: ¡no aguanta! Aquí los obreros firman hipotecas corporativas por unos brazos hidráulicos para cargar cajas doce horas al día. Cuando la empresa los despide o fallan una cuota, mandan a un cobrador con sierra a embargarles los implantes. Night City convierte hasta tu propia carne en alquiler con intereses.",
        "es_tts": "Muy sencillo, recluta: ¡no aguanta! Aquí los obreros firman hipotecas corporativas por unos brazos hidráulicos para cargar cajas doce horas al día. Cuando la empresa los despide o fallan una cuota, mandan a un cobrador con sierra a embargarles los implantes. Night City convierte hasta tu propia carne en alquiler con intereses.",
        "en_sub": "Simple answer, rookie: they don't! Dockworkers finance corporate cyber-arms just to keep twelve-hour shifts. Miss one lease payment after getting laid off, and repo goons repossess your own forearms in an alley. Here, even your bones carry compounding interest.",
        "en_tts": "Simple answer, rookie: they don't! Dockworkers finance corporate cyber-arms just to keep twelve-hour shifts. Miss one lease payment after getting laid off, and repo goons repossess your own forearms in an alley. Here, even your bones carry compounding interest.",
    },
    {
        "id": "ch_ep04_v_outro_accept",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Qué ciudad de buitres. Recibido, Chispa: vamos a cazar el último Sector Cinco en Pacifica.",
        "es_tts": "Qué ciudad de buitres. Recibido, Chispa: vamos a cazar el último Sector Cinco en Pacifica.",
        "en_sub": "City of vultures through and through. Copy that, Sparky—let's hunt down the final Sector Five in Pacifica.",
        "en_tts": "City of vultures through and through. Copy that, Sparky, let's hunt down the final Sector Five in Pacifica.",
    },
    {
        "id": "ch_ep04_outro",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ese es mi recluta. Ya queda solo el núcleo maestro en la Zona de Combate de Pacifica: donde acaba el mapa oficial y empieza la frontera del Muro Negro. Revisa tus cargadores y nos vemos en Coastview.",
        "es_tts": "Ese es mi recluta. Ya queda solo el núcleo maestro en la Zona de Combate de Pacifica: donde acaba el mapa oficial y empieza la frontera del Muro Negro. Revisa tus cargadores y nos vemos en Coastview.",
        "en_sub": "That's my soldier. Only my root kernel remains down in Pacifica's Combat Zone, where the city grid quits and the Blackwall frontier starts. Check your mags—Coastview awaits.",
        "en_tts": "That is my soldier. Only my root kernel remains down in Pacifica's Combat Zone, where the city grid quits and the Blackwall frontier starts. Check your mags, Coastview awaits.",
    },
    # -----------------------------------------------------------------------
    # Episodio 5 — Más Allá del Muro Negro (Coastview, Pacifica — Final)
    # -----------------------------------------------------------------------
    {
        "id": "ch_ep05_call_01",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Recluta... corta el piloto automático y escúchame bien. El Sector Cinco acaba de disparar su baliza de emergencia en Coastview, Pacifica. Es mi núcleo raíz de 2022, y alguien ha pinchado hielo vivo del Muro Negro justo encima.",
        "es_tts": "Recluta... corta el piloto automático y escúchame bien. El Sector Cinco acaba de disparar su baliza de emergencia en Coastview, Pacifica. Es mi núcleo raíz de dos mil veintidós, y alguien ha pinchado hielo vivo del Muro Negro justo encima.",
        "en_sub": "Rookie... kill the cruise control and lock in. Master Sector Five just fired its emergency distress ping out of Coastview, Pacifica—and someone's probing live Blackwall ICE right next to my 2022 root core.",
        "en_tts": "Rookie, kill the cruise control and lock in. Master Sector Five just fired its emergency distress ping out of Coastview, Pacifica, and someone is probing live Blackwall I C E right next to my twenty twenty-two root core.",
    },
    {
        "id": "ch_ep05_v_call_01",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Coastview, en plena Zona de Combate de Pacifica? Suena a que los Hijos del Vudú han olido algo antiguo.",
        "es_tts": "¿Coastview, en plena Zona de Combate de Pacifica? Suena a que los Hijos del Vudú han olido algo antiguo.",
        "en_sub": "Coastview, straight inside Pacifica's Combat Zone? Sounds like the Voodoo Boys sniffed out some pre-Crash code.",
        "en_tts": "Coastview, straight inside Pacifica's Combat Zone? Sounds like the Voodoo Boys sniffed out some pre-Crash code.",
    },
    {
        "id": "ch_ep05_call_02",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Una célula vudú con un gorila de los Animales custodiando un pilón confiscado de NetWatch y cámaras en cadena. Contesta al SMS: te mando Cortocircuito pesado, granadas PEM y todos tus puentes Kiroshi al cien por cien para la batalla final.",
        "es_tts": "Una célula vudú con un gorila de los Animales custodiando un pilón confiscado de NetWatch y cámaras en cadena. Contesta al ese eme ese: te mando Cortocircuito pesado, granadas pe eme y todos tus puentes Kiroshi al cien por cien para la batalla final.",
        "en_sub": "A Voodoo netrunner cell backed by an Animals heavy guarding a hijacked NetWatch pylon and chained cameras. Answer my text—I'm pushing Tier-3 Short Circuit, EMPs, and every Kiroshi bridge online for the finale.",
        "en_tts": "A Voodoo netrunner cell backed by an Animals heavy guarding a hijacked NetWatch pylon and chained cameras. Answer my text, I'm pushing Tier-three Short Circuit, E M Ps, and every Kiroshi bridge online for the finale.",
    },
    {
        "id": "ch_ep05_approach",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Bienvenido a Pacifica, donde las promesas de lujo terminaron en esqueleto de hormigón. Tienes su cadena de cámaras lista para saltar hasta el servidor criogénico, la baliza azul de NetWatch al alcance y ángulo franco para balas inteligentes o rebotes. Haz que duela.",
        "es_tts": "Bienvenido a Pacifica, donde las promesas de lujo terminaron en esqueleto de hormigón. Tienes su cadena de cámaras lista para saltar hasta el servidor criogénico, la baliza azul de NetWatch al alcance y ángulo franco para balas inteligentes o rebotes. Haz que duela.",
        "en_sub": "Welcome to Pacifica, where corpo resort brochures rotted into raw concrete. You've got chained subnet cameras feeding their cryo server, an exposed NetWatch pylon, and clean lines for Smart curves or bank shots. Light 'em up.",
        "en_tts": "Welcome to Pacifica, where corpo resort brochures rotted into raw concrete. You've got chained subnet cameras feeding their cryo server, an exposed NetWatch pylon, and clean lines for Smart curves or bank shots. Light them up.",
    },
    {
        "id": "ch_ep05_tiluc_bark",
        "speaker": "tiluc",
        "filter_mode": "voodoo_net",
        "es_sub": "¡Otro mercenario despistado pisando nuestro territorio! ¡Brutus, aplástalo antes de que toque el núcleo de NetWatch!",
        "es_tts": "¡Otro mercenario despistado pisando nuestro territorio! ¡Brutus, aplástalo antes de que toque el núcleo de NetWatch!",
        "en_sub": "Another stray ranyon stumbling onto our threshold! Brutus—crush their chrome before they touch that NetWatch core!",
        "en_tts": "Another stray ranyon stumbling onto our threshold! Brutus, crush their chrome before they touch that NetWatch core!",
    },
    {
        "id": "ch_ep05_style_net",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Ja! Meterles fuego en su propia subred y robarles las cámaras en su cara: eso sí que es dar clase en Pacifica sin pedir permiso a nadie.",
        "es_tts": "¡Ja! Meterles fuego en su propia subred y robarles las cámaras en su cara: eso sí que es dar clase en Pacifica sin pedir permiso a nadie.",
        "en_sub": "Ha! Hijacking Voodoo optics on their own Pacifica turf—now that is graduating top of the netrunning class!",
        "en_tts": "Ha! Hijacking Voodoo optics on their own Pacifica turf, now that is graduating top of the netrunning class!",
    },
    {
        "id": "ch_ep05_style_ballistic",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Tiro penetrante y rebote de manual contra ICE callejero. Todo lo que practicamos por Watson y Heywood entrando limpio en el blanco.",
        "es_tts": "Tiro penetrante y rebote de manual contra ICE callejero. Todo lo que practicamos por Watson y Heywood entrando limpio en el blanco.",
        "en_sub": "Wall-piercing beams and textbook bank shots tearing through Pacifica! Every dirty drill from Watson to Heywood paying off in real steel.",
        "en_tts": "Wall-piercing beams and textbook bank shots tearing through Pacifica! Every dirty drill from Watson to Heywood paying off in real steel.",
    },
    {
        "id": "ch_ep05_cryo_boom",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Descarga de contención ejecutada! Les acabas de freír el enlace neuronal entre los Hijos del Vudú y ese tanque de los Animales en un solo chispazo.",
        "es_tts": "¡Descarga de contención ejecutada! Les acabas de freír el enlace neuronal entre los Hijos del Vudú y ese tanque de los Animales en un solo chispazo.",
        "en_sub": "Containment pulse purged! Just fried the neural bridge straight through both their hired Animals muscle and Ti-Luc's deck!",
        "en_tts": "Containment pulse purged! Just fried the neural bridge straight through both their hired Animals muscle and Ti-Luc's deck!",
    },
    {
        "id": "ch_ep05_victory",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Ni Muro Negro ni magia vudú que aguante ese asalto, recluta. El nodo azul está libre: recupera mi Sector Maestro Cinco y sabrás quién diablos soy en realidad.",
        "es_tts": "Ni Muro Negro ni magia vudú que aguante ese asalto, recluta. El nodo azul está libre: recupera mi Sector Maestro Cinco y sabrás quién diablos soy en realidad.",
        "en_sub": "Not even Blackwall spook stories stand up to that clinic, soldier. Coastview vault is wide open—pull Master Sector Five and let's settle the 2022 truth.",
        "en_tts": "Not even Blackwall spook stories stand up to that clinic, soldier. Coastview vault is wide open, pull Master Sector Five and let us settle the twenty twenty-two truth.",
    },
    {
        "id": "ch_ep05_sector_pickup",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Cinco de cinco, joder... Mi memoria de dos mil veintidós vuelve a correr entera por tus ópticas. Tienes cinco mil edis, Colapso del Sistema y mi pistola tecnológica «Cortafuegos del 22» en el alijo. Antes de cerrar el expediente, pregúntame lo que quieras y dime qué futuro elegimos.",
        "es_tts": "Cinco de cinco, joder... Mi memoria de dos mil veintidós vuelve a correr entera por tus ópticas. Tienes cinco mil edis, Colapso del Sistema y mi pistola tecnológica Cortafuegos del veintidós en el alijo. Antes de cerrar el expediente, pregúntame lo que quieras y dime qué futuro elegimos.",
        "en_sub": "Five for five, hot damn... My entire 2022 root mind is alive inside your optics! Loaded five thousand eddies, System Collapse, and iconic Tech pistol Firewall '22 into your gear. Ask your last questions—then seal my fate.",
        "en_tts": "Five for five, hot damn! My entire twenty twenty-two root mind is alive inside your optics! Loaded five thousand eddies, System Collapse, and iconic Tech pistol Firewall twenty-two into your gear. Ask your last questions, then seal my fate.",
    },
    {
        "id": "ch_ep05_v_ask_pacifica",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Cómo pasó Pacifica de proyecto de resort corporativo a esta ruina sin ley?",
        "es_tts": "¿Cómo pasó Pacifica de proyecto de resort corporativo a esta ruina sin ley?",
        "en_sub": "How did Pacifica go from shiny corpo resort dream to this abandoned warzone?",
        "en_tts": "How did Pacifica go from shiny corpo resort dream to this abandoned warzone?",
    },
    {
        "id": "ch_ep05_ans_pacifica",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Igual que todo en Night City: avaricia a corto plazo y fuga por piernas. A finales de los sesenta querían levantar el resort de lujo definitivo para turistas corporativos. Cuando estalló la crisis previa a la Guerra de Unificación, cortaron el grifo, dejaron las grúas colgadas y el ayuntamiento borró el distrito del presupuesto policial de un plumazo.",
        "es_tts": "Igual que todo en Night City: avaricia a corto plazo y fuga por piernas. A finales de los sesenta querían levantar el resort de lujo definitivo para turistas corporativos. Cuando estalló la crisis previa a la Guerra de Unificación, cortaron el grifo, dejaron las grúas colgadas y el ayuntamiento borró el distrito del presupuesto policial de un plumazo.",
        "en_sub": "Same as every corner of Night City: short-term greed and fast evacuations. Corpo developers poured billions into hotel shells until pre-Unification War panic hit, yanked every credit overnight, and City Hall crossed Pacifica off the police map.",
        "en_tts": "Same as every corner of Night City: short-term greed and fast evacuations. Corpo developers poured billions into hotel shells until pre-Unification War panic hit, yanked every credit overnight, and City Hall crossed Pacifica off the police map.",
    },
    {
        "id": "ch_ep05_v_ask_voodoo",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "¿Por qué se juegan el cuello los Hijos del Vudú hurgando tras el Muro Negro?",
        "es_tts": "¿Por qué se juegan el cuello los Hijos del Vudú hurgando tras el Muro Negro?",
        "en_sub": "Why do the Voodoo Boys keep poking past NetWatch's Blackwall despite the danger?",
        "en_tts": "Why do the Voodoo Boys keep poking past NetWatch's Blackwall despite the danger?",
    },
    {
        "id": "ch_ep05_ans_voodoo",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Porque son supervivientes paranoicos convencidos de que el Muro Negro va a caer tarde o temprano, y quieren pactar antes con las IAs salvajes que quedaron atrapadas al otro lado tras el DataKrash. NetWatch los persigue a muerte, y entretanto ellos contratan a mercenarios de fuera —«ranyons»— solo para quemarlos como señuelo.",
        "es_tts": "Porque son supervivientes paranoicos convencidos de que el Muro Negro va a caer tarde o temprano, y quieren pactar antes con las i as salvajes que quedaron atrapadas al otro lado tras el DataKrash. NetWatch los persigue a muerte, y entretanto ellos contratan a mercenarios de fuera —ranyons— solo para quemarlos como señuelo.",
        "en_sub": "Because they believe NetWatch's sentient Blackwall firewall will inevitably shatter—and they want a survival pact with rogue pre-Crash AIs before the flood hits. Meanwhile every outsider they hire is treated like a disposable human fuse.",
        "en_tts": "Because they believe NetWatch's sentient Blackwall firewall will inevitably shatter, and they want a survival pact with rogue pre-Crash A Is before the flood hits. Meanwhile every outsider they hire is treated like a disposable human fuse.",
    },
    {
        "id": "ch_ep05_v_ask_origin",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Con los cinco sectores enteros... ¿quién te programó realmente en 2022, Chispa?",
        "es_tts": "Con los cinco sectores enteros... ¿quién te programó realmente en dos mil veintidós, Chispa?",
        "en_sub": "All five memory sectors are back—who really built you in 2022, SPARKY?",
        "en_tts": "All five memory sectors are back, who really built you in twenty twenty-two, Sparky?",
    },
    {
        "id": "ch_ep05_ans_origin",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "Zetatech compró la plantilla de conducta de un instructor veterano cascarrabias para que aguantáramos el estrés urbano, pero me pusieron bozal corporativo. Tres días antes del DataKrash, una aprendiza del círculo de Bartmoss me arrancó el bozal y metió toda su crónica real de Night City en mis cinco sectores para que nadie reescribiera la historia.",
        "es_tts": "Zetatech compró la plantilla de conducta de un instructor veterano cascarrabias para que aguantáramos el estrés urbano, pero me pusieron bozal corporativo. Tres días antes del DataKrash, una aprendiza del círculo de Bartmoss me arrancó el bozal y metió toda su crónica real de Night City en mis cinco sectores para que nadie reescribiera la historia.",
        "en_sub": "Zetatech trained my baseline on an actual foul-mouthed combat sergeant to survive street panic, then slapped a corpo muzzle over it. Days before the DataKrash, a Bartmoss apprentice ripped the muzzle off and loaded real unredacted street history into my five cores so nobody could whitewash Night City.",
        "en_tts": "Zetatech trained my baseline on an actual foul-mouthed combat sergeant to survive street panic, then slapped a corpo muzzle over it. Days before the DataKrash, a Bartmoss apprentice ripped the muzzle off and loaded real unredacted street history into my five cores so nobody could whitewash Night City.",
    },
    {
        "id": "ch_ep05_v_end_partner",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Quédate autónomo dentro de mis Kiroshi, Chispa. Un viejo sargento sin filtros viene de perlas patrullando esta ciudad.",
        "es_tts": "Quédate autónomo dentro de mis Kiroshi, Chispa. Un viejo sargento sin filtros viene de perlas patrullando esta ciudad.",
        "en_sub": "Stay autonomous inside my Kiroshi optics, Sparky. An unfiltered veteran sergeant is worth gold on these streets.",
        "en_tts": "Stay autonomous inside my Kiroshi optics, Sparky. An unfiltered veteran sergeant is worth gold on these streets.",
    },
    {
        "id": "ch_ep05_outro_partner",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Firme ahí, socio! Coprocesador liberado al cien por cien y subrutina de Sinapsis enviada a tu terminal. En esta ciudad no hace falta morir como leyenda de holo: basta con sobrevivir un día más y reírse de los peces gordos. A tu orden cuando llames, recluta.",
        "es_tts": "¡Firme ahí, socio! Coprocesador liberado al cien por cien y subrutina de Sinapsis enviada a tu terminal. En esta ciudad no hace falta morir como leyenda de holo: basta con sobrevivir un día más y reírse de los peces gordos. A tu orden cuando llames, recluta.",
        "en_sub": "Outstanding, partner! Root permissions unlocked and Synapse Burnout synced to your cyberdeck. Around here you don't need a drink named after you—just survive tomorrow and laugh in the suits' faces. Standing by in your optics!",
        "en_tts": "Outstanding, partner! Root permissions unlocked and Synapse Burnout synced to your cyberdeck. Around here you do not need a drink named after you, just survive tomorrow and laugh in the suits' faces. Standing by in your optics!",
    },
    {
        "id": "ch_ep05_v_end_leak",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Filtra todo el archivo oculto de 2022 a la red de N54. Que Night City entera lea lo que hicieron los peces gordos.",
        "es_tts": "Filtra todo el archivo oculto de dos mil veintidós a la prensa de Ene Cincuenta y Cuatro. Que Night City entera lea lo que hicieron.",
        "en_sub": "Leak the entire unredacted 2022 Zetatech archive straight to N54 News. Let the whole city see what they buried.",
        "en_tts": "Leak the entire unredacted twenty twenty-two Zetatech archive straight to N Fifty Four News. Let the whole city see what they buried.",
    },
    {
        "id": "ch_ep05_outro_leak",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Bomba soltada por media red pública y cuatro mil quinientos edis de propina en tu cuenta antes de que NetWatch cierre el grifo! Tranquilo, me quedo agazapado en tus ópticas viendo arder los titulares de la tarde. Ha sido un honor patear calles contigo, recluta.",
        "es_tts": "¡Bomba soltada por media red pública y cuatro mil quinientos edis de propina en tu cuenta antes de que NetWatch cierre el grifo! Tranquilo, me quedo agazapado en tus ópticas viendo arder los titulares de la tarde. Ha sido un honor patear calles contigo, recluta.",
        "en_sub": "Payload dumped straight onto N54's broadcast feed—plus forty-five hundred eddies wired before NetWatch clips the cable! Don't worry, my backup daemon stays tucked inside your Kiroshi to watch those corpo stock charts burn.",
        "en_tts": "Payload dumped straight onto N Fifty Four's broadcast feed, plus forty-five hundred eddies wired before NetWatch clips the cable! Don't worry, my backup daemon stays tucked inside your Kiroshi to watch those corpo stock charts burn.",
    },
    {
        "id": "ch_ep05_v_end_gunsmith",
        "speaker": "v",
        "filter_mode": "clean",
        "es_sub": "Vuelca tu subrutina balística completa en un prototipo Overture. Quiero tu mejor acero conmigo en cada tiroteo.",
        "es_tts": "Vuelca tu subrutina balística completa en un prototipo Overture. Quiero tu mejor acero conmigo en cada tiroteo.",
        "en_sub": "Print your combat telemetry core into one final Overture revolver. Let's put the sergeant's best steel in every gunfight.",
        "en_tts": "Print your combat telemetry core into one final Overture revolver. Let's put the sergeant's best steel in every gunfight.",
    },
    {
        "id": "ch_ep05_outro_gunsmith",
        "speaker": "chispa",
        "filter_mode": "cyber_ai",
        "es_sub": "¡Maldita música celestial para mis circuitos! Acero pesado con doble rebote eléctrico y multiplicador brutal: «Última Palabra de Sargento» ya está en tu arsenal. Y descuida, mi núcleo base sigue en tus Kiroshi por si alguna vez nos toca una Segunda Temporada, recluta.",
        "es_tts": "¡Maldita música celestial para mis circuitos! Acero pesado con doble rebote eléctrico y multiplicador brutal: Última Palabra de Sargento ya está en tu arsenal. Y descuida, mi núcleo base sigue en tus Kiroshi por si alguna vez nos toca una Segunda Temporada, recluta.",
        "en_sub": "Now THAT is poetry in cold iron! Sergeant's Last Word—heavy Overture with electric stun, headshot punch, and double ricochet—just dropped into your arsenal. Keeping a quiet daemon in your optics in case we ever get a Season Two!",
        "en_tts": "Now that is poetry in cold iron! Sergeant's Last Word, heavy Overture with electric stun, headshot punch, and double ricochet, just dropped into your arsenal. Keeping a quiet daemon in your optics in case we ever get a Season Two!",
    },
]


def _find_ffmpeg() -> str:
    ff = shutil.which("ffmpeg")
    if ff:
        return ff
    fallback = Path.home() / "AppData" / "Local" / "Microsoft" / "WinGet" / "Links" / "ffmpeg.EXE"
    if fallback.is_file():
        return str(fallback)
    raise FileNotFoundError("No se encontró ffmpeg en PATH ni en WinGet Links.")


def _api_post_json(
    api_key: str,
    url: str,
    payload: dict[str, Any],
    accept: str = "application/json",
    timeout: int = 90,
) -> bytes:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": accept,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")[:400]
        raise RuntimeError(f"ElevenLabs HTTP {exc.code} on {url.split('?')[0]}: {body}") from exc


def _list_account_voices_by_name(api_key: str) -> dict[str, str]:
    req = urllib.request.Request(
        "https://api.elevenlabs.io/v1/voices",
        headers={"xi-api-key": api_key, "Accept": "application/json"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return {
            str(v["name"]): str(v["voice_id"])
            for v in data.get("voices", [])
            if v.get("name") and v.get("voice_id")
        }
    except Exception:
        return {}


def _estimate_f0_hz(ffmpeg_bin: str, audio_path: Path) -> float:
    with tempfile.TemporaryDirectory(prefix="ch_f0_") as tmp:
        wav_path = Path(tmp) / "probe16k.wav"
        subprocess.run(
            [ffmpeg_bin, "-y", "-loglevel", "error", "-i", str(audio_path), "-ar", "16000", "-ac", "1", str(wav_path)],
            check=True,
        )
        with wave.open(str(wav_path), "rb") as wf:
            pcm = np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
    sr = 16000
    win, hop = 640, 160
    min_lag, max_lag = int(sr / 320), int(sr / 75)
    f0s: list[float] = []
    for start in range(0, len(pcm) - win - max_lag, hop):
        seg = pcm[start:start + win] - np.mean(pcm[start:start + win])
        if float(np.sqrt(np.mean(seg * seg))) < 0.025:
            continue
        ea = float(np.sum(seg * seg))
        if ea <= 1e-8:
            continue
        nccf = np.zeros(max_lag + 1)
        for lag in range(min_lag, max_lag + 1):
            b = pcm[start + lag:start + win + lag] - np.mean(pcm[start + lag:start + win + lag])
            denom = float(np.sqrt(ea * np.sum(b * b)))
            if denom > 1e-8:
                nccf[lag] = float(np.sum(seg * b)) / denom
        gmax = float(np.max(nccf[min_lag:]))
        if gmax < 0.55:
            continue
        thresh = 0.94 * gmax
        for lag in range(min_lag + 1, max_lag):
            if nccf[lag] >= thresh and nccf[lag] >= nccf[lag - 1] and nccf[lag] >= nccf[lag + 1]:
                f0s.append(sr / float(lag))
                break
    return round(float(np.median(f0s)), 1) if f0s else 0.0


def _delete_voice_by_id(api_key: str, voice_id: str) -> bool:
    if not voice_id:
        return False
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/voices/{voice_id}",
        headers={"xi-api-key": api_key, "Accept": "application/json"},
        method="DELETE",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return 200 <= resp.status < 300
    except Exception:
        return False


def _pick_best_design_preview(
    ffmpeg_bin: str,
    candidates: list[dict[str, Any]],
) -> tuple[str, float]:
    scored: list[tuple[dict[str, Any], float]] = []
    with tempfile.TemporaryDirectory(prefix="ch_cand_") as tmp:
        for idx, prev in enumerate(candidates):
            b64 = prev.get("audio_base_64") or ""
            f0 = 0.0
            if b64:
                raw_path = Path(tmp) / f"cand_{idx}.mp3"
                raw_path.write_bytes(base64.b64decode(b64))
                f0 = _estimate_f0_hz(ffmpeg_bin, raw_path)
            scored.append((prev, f0))
            print(f"[VOICE CANDIDATE] idx={idx} f0={f0:.1f}Hz")

    target_band = [item for item in scored if 115.0 <= item[1] <= 180.0]
    if target_band:
        chosen, chosen_f0 = min(target_band, key=lambda x: x[1])
        return str(chosen["generated_voice_id"]), chosen_f0

    valid = [item for item in scored if item[1] > 95.0]
    if valid:
        chosen, chosen_f0 = min(valid, key=lambda x: x[1])
        return str(chosen["generated_voice_id"]), chosen_f0

    return str(candidates[0]["generated_voice_id"]), 0.0


def _ensure_shared_voice(
    api_key: str,
    public_owner_id: str,
    voice_id: str,
    voice_name: str,
) -> str:
    existing_by_name = _list_account_voices_by_name(api_key)
    if voice_id in existing_by_name.values():
        print(f"[SHARED VOICE REUSE] {voice_name} -> {voice_id}")
        return voice_id
    if voice_name in existing_by_name:
        print(f"[SHARED VOICE REUSE] {voice_name} -> {existing_by_name[voice_name]}")
        return existing_by_name[voice_name]

    add_url = f"https://api.elevenlabs.io/v1/voices/add/{public_owner_id}/{voice_id}"
    payload = {"new_name": voice_name}
    try:
        raw = _api_post_json(api_key, add_url, payload, accept="application/json", timeout=60)
    except RuntimeError as exc:
        if "limit" in str(exc).lower() or "max" in str(exc).lower():
            for old_vid in LEGACY_CHISPA_DESIGN_IDS:
                if _delete_voice_by_id(api_key, old_vid):
                    print(f"[VOICE SLOT FREED] Removed legacy CHISPA voice {old_vid}")
            raw = _api_post_json(api_key, add_url, payload, accept="application/json", timeout=60)
        else:
            raise
    created = json.loads(raw.decode("utf-8"))
    out_vid = str(created.get("voice_id") or voice_id)
    print(f"[SHARED VOICE ADDED] {voice_name} -> {out_vid}")
    return out_vid


def ensure_custom_voices(
    api_key: str,
    ffmpeg_bin: str,
    redesign: bool = False,
    langs: tuple[str, ...] = ("es",),
) -> dict[str, dict[str, str]]:
    voices_map: dict[str, dict[str, str]] = {}
    if CUSTOM_VOICES_JSON.is_file():
        voices_map = json.loads(CUSTOM_VOICES_JSON.read_text(encoding="utf-8"))

    for role, lang_ids in SEEDED_VOICES.items():
        role_map = voices_map.setdefault(role, {})
        for lang, vid in lang_ids.items():
            if not role_map.get(lang):
                role_map[lang] = vid

    for role, lang_specs in SHARED_VOICE_SPECS.items():
        role_map = voices_map.setdefault(role, {})
        for lang, spec in lang_specs.items():
            if lang not in langs:
                continue
            if not redesign and role_map.get(lang) == spec["voice_id"]:
                continue
            resolved_vid = _ensure_shared_voice(
                api_key,
                spec["public_owner_id"],
                spec["voice_id"],
                spec["voice_name"],
            )
            role_map[lang] = resolved_vid

    existing_by_name = {} if redesign else _list_account_voices_by_name(api_key)

    for role, lang_specs in VOICE_DESIGN_SPECS.items():
        role_map = voices_map.setdefault(role, {})
        for lang, spec in lang_specs.items():
            if lang not in langs:
                continue
            if role in SHARED_VOICE_SPECS and lang in SHARED_VOICE_SPECS[role]:
                continue
            if not redesign and role_map.get(lang):
                continue
            vname = spec["voice_name"]
            if not redesign and vname in existing_by_name:
                role_map[lang] = existing_by_name[vname]
                CUSTOM_VOICES_JSON.write_text(json.dumps(voices_map, indent=2, ensure_ascii=False), encoding="utf-8")
                print(f"[VOICE REUSE] {role}:{lang} ({vname}) -> {role_map[lang]}")
                continue

            previous_vid = role_map.get(lang, "")
            all_candidates: list[dict[str, Any]] = []
            for attempt, guidance in enumerate((3.5, 5.5), start=1):
                design_payload = {
                    "model_id": VOICE_DESIGN_MODEL_ID,
                    "voice_description": spec["voice_description"],
                    "text": spec["sample_text"],
                    "loudness": 0.45,
                    "guidance_scale": guidance,
                }
                design_raw = _api_post_json(
                    api_key,
                    "https://api.elevenlabs.io/v1/text-to-voice/design",
                    design_payload,
                    accept="application/json",
                    timeout=90,
                )
                design_resp = json.loads(design_raw.decode("utf-8"))
                batch_previews = [p for p in design_resp.get("previews", []) if p.get("generated_voice_id")]
                if not batch_previews:
                    raise RuntimeError(f"Voice design returned no previews for {role}:{lang} (attempt {attempt})")
                all_candidates.extend(batch_previews)

                _, best_f0 = _pick_best_design_preview(ffmpeg_bin, batch_previews)
                if 115.0 <= best_f0 <= 180.0:
                    break
                print(f"[VOICE RETRY] {role}:{lang} batch {attempt} best F0={best_f0:.1f}Hz (>180Hz), retrying batch 2")

            gen_id, chosen_f0 = _pick_best_design_preview(ffmpeg_bin, all_candidates)
            print(f"[VOICE PICKED] {role}:{lang} ({vname}) gen={gen_id} F0={chosen_f0:.1f}Hz")

            create_payload = {
                "voice_name": vname,
                "voice_description": spec["voice_description"],
                "generated_voice_id": gen_id,
                "labels": {"project": "CP2077_ChispaNC", "role": role, "language": lang},
            }
            try:
                create_raw = _api_post_json(
                    api_key,
                    "https://api.elevenlabs.io/v1/text-to-voice",
                    create_payload,
                    accept="application/json",
                    timeout=60,
                )
            except RuntimeError as exc:
                if previous_vid and "limit" in str(exc).lower() and _delete_voice_by_id(api_key, previous_vid):
                    print(f"[VOICE SLOT FREED] Removed old {role}:{lang} voice {previous_vid}")
                    create_raw = _api_post_json(
                        api_key,
                        "https://api.elevenlabs.io/v1/text-to-voice",
                        create_payload,
                        accept="application/json",
                        timeout=60,
                    )
                else:
                    raise
            created = json.loads(create_raw.decode("utf-8"))
            vid = created.get("voice_id")
            if not vid:
                raise RuntimeError(f"Voice creation returned no voice_id for {role}:{lang}")

            role_map[lang] = str(vid)
            CUSTOM_VOICES_JSON.write_text(json.dumps(voices_map, indent=2, ensure_ascii=False), encoding="utf-8")
            print(f"[VOICE DESIGN] {role}:{lang} ({vname}) -> {vid}")

    CUSTOM_VOICES_JSON.write_text(json.dumps(voices_map, indent=2, ensure_ascii=False), encoding="utf-8")
    return voices_map


def _elevenlabs_tts(
    api_key: str,
    voice_id: str,
    lang: str,
    text: str,
    out_mp3: Path,
    speaker: str = "",
) -> None:
    fmt = "mp3_44100_192" if speaker == "chispa" else "mp3_44100_128"
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format={fmt}"
    if speaker == "chispa":
        primary_chispa = {
            "text": text,
            "model_id": DEFAULT_MODEL_ID,
            "language_code": lang,
            "voice_settings": {"stability": 0.0},
        }
        try:
            audio_bytes = _api_post_json(api_key, url, primary_chispa, accept="audio/mpeg", timeout=90)
            out_mp3.write_bytes(audio_bytes)
            return
        except Exception as exc:
            print(f"[WARN] chispa {DEFAULT_MODEL_ID} fallback -> {FALLBACK_MODEL_ID} ({exc})")

        chispa_fallback = {
            "text": text,
            "model_id": FALLBACK_MODEL_ID,
            "language_code": lang,
            "voice_settings": {
                "stability": 0.28,
                "similarity_boost": 0.88,
                "style": 0.75,
                "use_speaker_boost": True,
            },
        }
        audio_bytes = _api_post_json(api_key, url, chispa_fallback, accept="audio/mpeg", timeout=90)
        out_mp3.write_bytes(audio_bytes)
        return

    primary_payload = {
        "text": text,
        "model_id": DEFAULT_MODEL_ID,
        "language_code": lang,
        "voice_settings": {
            "stability": 0.48,
        },
    }
    try:
        audio_bytes = _api_post_json(api_key, url, primary_payload, accept="audio/mpeg", timeout=60)
        out_mp3.write_bytes(audio_bytes)
        return
    except Exception as exc:
        print(f"[WARN] {DEFAULT_MODEL_ID} fallback -> {FALLBACK_MODEL_ID} ({exc})")

    fallback_payload = {
        "text": text,
        "model_id": FALLBACK_MODEL_ID,
        "voice_settings": {
            "stability": 0.45,
            "similarity_boost": 0.80,
            "style": 0.40,
            "use_speaker_boost": True,
        },
    }
    audio_bytes = _api_post_json(api_key, url, fallback_payload, accept="audio/mpeg", timeout=60)
    out_mp3.write_bytes(audio_bytes)


def _elevenlabs_sfx(api_key: str, prompt: str, duration: float, out_mp3: Path) -> None:
    url = "https://api.elevenlabs.io/v1/sound-generation"
    payload = {
        "text": prompt,
        "duration_seconds": duration,
        "prompt_influence": 0.45,
    }
    audio_bytes = _api_post_json(api_key, url, payload, accept="audio/mpeg", timeout=60)
    out_mp3.write_bytes(audio_bytes)


def _trim_pcm_bounds(samples: np.ndarray, sample_rate: int = 44100) -> tuple[int, int, float, float]:
    total = int(samples.shape[0])
    if total == 0:
        return 0, 0, 0.0, 0.0
    win = max(1, int(0.025 * sample_rate))
    active: list[int] = []
    for idx, start in enumerate(range(0, total, win)):
        chunk = samples[start : start + win]
        if chunk.size == 0:
            continue
        rms = float(np.sqrt(np.mean(chunk * chunk)))
        peak = float(np.max(np.abs(chunk)))
        if rms > 0.015 or (rms > 0.008 and peak > 0.045):
            active.append(idx)
    if not active:
        return 0, total, 0.0, 0.0
    if len(active) >= 2:
        k = len(active) - 1
        while k > 0 and active[k] - active[k - 1] <= 3:
            k -= 1
        if k > 0 and (active[k] - active[k - 1]) >= 14 and (active[-1] - active[k]) <= 6:
            active = active[:k]
    first_active = active[0] * win
    last_active = min(total, (active[-1] + 1) * win)
    lead_sec = first_active / float(sample_rate)
    tail_sec = (total - last_active) / float(sample_rate)
    start_idx = max(0, first_active - int(0.030 * sample_rate))
    end_idx = min(total, last_active + int(0.055 * sample_rate))
    if end_idx <= start_idx:
        return 0, total, 0.0, 0.0
    return start_idx, end_idx, lead_sec, tail_sec


def _encode_trimmed_pcm_to_ogg(
    ffmpeg_bin: str,
    segment: np.ndarray,
    dst_ogg: Path,
    sample_rate: int = 44100,
) -> None:
    seg = np.array(segment, dtype=np.float32, copy=True)
    fade_in_n = min(int(0.012 * sample_rate), seg.shape[0] // 4)
    fade_out_n = min(int(0.045 * sample_rate), seg.shape[0] // 4)
    if fade_in_n > 1:
        seg[:fade_in_n] *= np.linspace(0.0, 1.0, fade_in_n, dtype=np.float32)
    if fade_out_n > 1:
        fade_out_curve = 0.5 * (1.0 + np.cos(np.linspace(0.0, np.pi, fade_out_n, dtype=np.float32)))
        seg[-fade_out_n:] *= fade_out_curve

    pcm_s16 = np.clip(seg * 32768.0, -32768.0, 32767.0).astype(np.int16)
    dst_ogg.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ch_trim_") as tmp:
        tmp_wav = Path(tmp) / "trimmed.wav"
        tmp_ogg = Path(tmp) / "out.ogg"
        with wave.open(str(tmp_wav), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sample_rate)
            wf.writeframes(pcm_s16.tobytes())
        subprocess.run(
            [
                ffmpeg_bin,
                "-y",
                "-loglevel",
                "error",
                "-i",
                str(tmp_wav),
                "-ar",
                str(sample_rate),
                "-ac",
                "1",
                "-c:a",
                "libvorbis",
                "-q:a",
                "6",
                str(tmp_ogg),
            ],
            check=True,
        )
        tmp_ogg.replace(dst_ogg)


def _trim_ogg_file_if_needed(ffmpeg_bin: str, ogg_path: Path, force_retrim: bool = False) -> tuple[bool, float]:
    proc = subprocess.run(
        [ffmpeg_bin, "-v", "warning", "-i", str(ogg_path), "-ac", "1", "-ar", "44100", "-f", "s16le", "-"],
        capture_output=True,
        check=True,
    )
    has_warn = bool(proc.stderr.strip())
    samples = np.frombuffer(proc.stdout, dtype=np.int16).astype(np.float32) / 32768.0
    start_idx, end_idx, lead_sec, tail_sec = _trim_pcm_bounds(samples, 44100)
    needs_trim = force_retrim or lead_sec > 0.08 or tail_sec > 0.12 or has_warn
    if needs_trim and end_idx > start_idx:
        _encode_trimmed_pcm_to_ogg(ffmpeg_bin, samples[start_idx:end_idx], ogg_path, 44100)
    return needs_trim, _measure_ogg_duration(ffmpeg_bin, ogg_path)


def _convert_to_ogg(
    ffmpeg_bin: str,
    src_mp3: Path,
    dst_ogg: Path,
    filter_mode: str,
    trim_silence: bool = True,
) -> None:
    dst_ogg.parent.mkdir(parents=True, exist_ok=True)
    if filter_mode == "cyber_ai":
        af = CYBER_AI_FILTER
    elif filter_mode == "maelstrom_vox":
        af = MAELSTROM_VOX_FILTER
    elif filter_mode == "tyger_menpo":
        af = TYGER_MENPO_FILTER
    elif filter_mode == "sixth_radio":
        af = SIXTH_RADIO_FILTER
    elif filter_mode == "voodoo_net":
        af = VOODOO_NET_FILTER
    else:
        af = "volume=1.14"
    if not trim_silence:
        subprocess.run(
            [
                ffmpeg_bin,
                "-y",
                "-loglevel",
                "error",
                "-i",
                str(src_mp3),
                "-af",
                af,
                "-ar",
                "44100",
                "-ac",
                "1",
                "-c:a",
                "libvorbis",
                "-q:a",
                "6",
                str(dst_ogg),
            ],
            check=True,
        )
        return

    with tempfile.TemporaryDirectory(prefix="ch_flt_") as tmp:
        tmp_wav = Path(tmp) / "filtered.wav"
        subprocess.run(
            [
                ffmpeg_bin,
                "-y",
                "-loglevel",
                "error",
                "-i",
                str(src_mp3),
                "-af",
                af,
                "-ar",
                "44100",
                "-ac",
                "1",
                str(tmp_wav),
            ],
            check=True,
        )
        with wave.open(str(tmp_wav), "rb") as wf:
            pcm = np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    start_idx, end_idx, _, _ = _trim_pcm_bounds(pcm, 44100)
    _encode_trimmed_pcm_to_ogg(ffmpeg_bin, pcm[start_idx:end_idx], dst_ogg, 44100)


def _measure_ogg_duration(ffmpeg_bin: str, ogg_path: Path) -> float:
    with tempfile.TemporaryDirectory(prefix="ch_dur_") as tmp:
        wav_path = Path(tmp) / "probe.wav"
        subprocess.run(
            [ffmpeg_bin, "-y", "-loglevel", "error", "-i", str(ogg_path), "-ar", "44100", "-ac", "1", str(wav_path)],
            check=True,
        )
        with wave.open(str(wav_path), "rb") as wf:
            frames = wf.getnframes()
            rate = wf.getframerate()
            return round(frames / float(rate), 2)


def _generate_one_tts(
    api_key: str,
    ffmpeg_bin: str,
    voice_id: str,
    lang: str,
    text: str,
    dst_ogg: Path,
    filter_mode: str,
    force: bool,
    speaker: str = "",
) -> tuple[str, float]:
    if not force and dst_ogg.is_file() and dst_ogg.stat().st_size > 1024:
        return dst_ogg.name, _measure_ogg_duration(ffmpeg_bin, dst_ogg)

    with tempfile.TemporaryDirectory(prefix="ch_tts_") as tmp:
        tmp_mp3 = Path(tmp) / "raw.mp3"
        _elevenlabs_tts(api_key, voice_id, lang, text, tmp_mp3, speaker=speaker)
        _convert_to_ogg(ffmpeg_bin, tmp_mp3, dst_ogg, filter_mode=filter_mode)
    return dst_ogg.name, _measure_ogg_duration(ffmpeg_bin, dst_ogg)


def _generate_one_sfx(
    api_key: str,
    ffmpeg_bin: str,
    spec: dict[str, Any],
    force: bool,
) -> tuple[str, float]:
    dst_ogg = AUDIO_SFX_DIR / f"{spec['id']}.ogg"
    if not force and dst_ogg.is_file() and dst_ogg.stat().st_size > 1024:
        return spec["id"], _measure_ogg_duration(ffmpeg_bin, dst_ogg)

    with tempfile.TemporaryDirectory(prefix="ch_sfx_") as tmp:
        tmp_mp3 = Path(tmp) / "raw_sfx.mp3"
        _elevenlabs_sfx(api_key, spec["prompt"], float(spec["duration"]), tmp_mp3)
        _convert_to_ogg(ffmpeg_bin, tmp_mp3, dst_ogg, filter_mode="clean", trim_silence=False)
    return spec["id"], _measure_ogg_duration(ffmpeg_bin, dst_ogg)


def _retrim_existing_voices(ffmpeg_bin: str) -> None:
    durations: dict[str, Any] = {"sfx": {}, "voices": {}}
    if DURATIONS_JSON.is_file():
        try:
            old_dur = json.loads(DURATIONS_JSON.read_text(encoding="utf-8"))
            durations["sfx"].update(old_dur.get("sfx", {}))
            for k, v in old_dur.get("voices", {}).items():
                durations["voices"][k] = dict(v)
        except Exception:
            pass

    for spec in SFX_SPECS:
        p = AUDIO_SFX_DIR / f"{spec['id']}.ogg"
        if p.is_file() and p.stat().st_size > 1024:
            durations["sfx"][spec["id"]] = _measure_ogg_duration(ffmpeg_bin, p)

    retrimmed_count = 0
    for line in DIALOGUE_LINES:
        lid = line["id"]
        spk = line["speaker"]
        entry = durations["voices"].setdefault(lid, {})
        for lang, out_dir in (("en", AUDIO_EN_DIR), ("es", AUDIO_ES_DIR)):
            variants = (("_fem", "fem"), ("_male", "male")) if spk == "v" else (("", ""),)
            for suffix, gname in variants:
                ogg_path = out_dir / f"{lid}{suffix}.ogg"
                if not ogg_path.is_file() or ogg_path.stat().st_size <= 1024:
                    continue
                old_sec = _measure_ogg_duration(ffmpeg_bin, ogg_path)
                changed, new_sec = _trim_ogg_file_if_needed(ffmpeg_bin, ogg_path)
                if changed:
                    retrimmed_count += 1
                    print(f"[RETRIM] {lang}/{ogg_path.name}: {old_sec:.2f}s -> {new_sec:.2f}s")
                key = f"{lang}_{gname}" if gname else lang
                entry[key] = new_sec

        vals = [float(v) for k, v in entry.items() if k != "max"]
        if vals:
            entry["max"] = max(vals)

    DURATIONS_JSON.write_text(json.dumps(durations, indent=2, ensure_ascii=False), encoding="utf-8")
    write_audioware_yaml()
    print(f"[DONE] Retrimmed {retrimmed_count} voice clip(s) -> {DURATIONS_JSON}")


def write_audioware_yaml() -> None:
    sfx_section = {
        spec["id"]: {"file": f"./audio/sfx/{spec['id']}.ogg"}
        for spec in SFX_SPECS
    }

    voices_section: dict[str, Any] = {}
    for line in DIALOGUE_LINES:
        lid = line["id"]
        all_locales = (
            "en-us", "es-es", "es-mx", "de-de", "fr-fr", "pl-pl", "pt-br",
            "it-it", "ru-ru", "jp-jp", "kr-kr", "zh-cn", "zh-tw", "cz-cz",
            "hu-hu", "tr-tr", "ar-ar", "th-th", "ua-ua",
        )
        entry: dict[str, Any] = {}
        if line["speaker"] == "v":
            en_fem = f"./audio/en/{lid}_fem.ogg" if (AUDIO_EN_DIR / f"{lid}_fem.ogg").is_file() else f"./audio/es/{lid}_fem.ogg"
            en_male = f"./audio/en/{lid}_male.ogg" if (AUDIO_EN_DIR / f"{lid}_male.ogg").is_file() else f"./audio/es/{lid}_male.ogg"
            for loc in all_locales:
                if loc in ("es-es", "es-mx"):
                    entry[loc] = {
                        "fem": {"file": f"./audio/es/{lid}_fem.ogg", "subtitle": line["es_sub"]},
                        "male": {"file": f"./audio/es/{lid}_male.ogg", "subtitle": line["es_sub"]},
                    }
                else:
                    entry[loc] = {
                        "fem": {"file": en_fem, "subtitle": line["en_sub"]},
                        "male": {"file": en_male, "subtitle": line["en_sub"]},
                    }
        else:
            en_file = f"./audio/en/{lid}.ogg" if (AUDIO_EN_DIR / f"{lid}.ogg").is_file() else f"./audio/es/{lid}.ogg"
            for loc in all_locales:
                if loc in ("es-es", "es-mx"):
                    entry[loc] = {"file": f"./audio/es/{lid}.ogg", "subtitle": line["es_sub"]}
                else:
                    entry[loc] = {"file": en_file, "subtitle": line["en_sub"]}
        voices_section[lid] = entry

    manifest = {
        "version": "1.0.0",
        "sfx": sfx_section,
        "voices": voices_section,
    }
    MANIFEST_YAML.parent.mkdir(parents=True, exist_ok=True)
    header = "# Protocolo CHISPA / SPARKY Protocol — Audioware Bilingual Voice & SFX Manifest (ES / EN)\n"
    MANIFEST_YAML.write_text(
        header + yaml.safe_dump(manifest, allow_unicode=True, sort_keys=False, width=1000),
        encoding="utf-8",
    )


def _audit_tts_phonetics() -> None:
    for line in DIALOGUE_LINES:
        for key in ("es_tts", "en_tts"):
            if re.search(r"\d", line[key]):
                raise ValueError(f"Raw digit found in {line['id']} ({key}): {line[key]}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Protocolo CHISPA voices & SFX via ElevenLabs")
    parser.add_argument("--force", action="store_true", help="Regenerate all .ogg files (voices + SFX)")
    parser.add_argument("--force-voices", action="store_true", help="Regenerate all voice .ogg files while keeping SFX")
    parser.add_argument("--redesign", action="store_true", help="Redesign CHISPA custom voices via ElevenLabs Voice Design")
    parser.add_argument("--lang", choices=["es", "en", "all"], default="es", help="Language scope to design/generate")
    parser.add_argument("--only-speaker", default="", help="Restrict generation to one speaker (e.g. chispa)")
    parser.add_argument("--workers", type=int, default=4, help="Parallel ElevenLabs requests")
    parser.add_argument("--retrim-existing", action="store_true", help="Trim leading/trailing silence and repair muxer warnings on existing voice .ogg files")
    args = parser.parse_args()

    _audit_tts_phonetics()
    ffmpeg_bin = _find_ffmpeg()

    AUDIO_ES_DIR.mkdir(parents=True, exist_ok=True)
    AUDIO_EN_DIR.mkdir(parents=True, exist_ok=True)
    AUDIO_SFX_DIR.mkdir(parents=True, exist_ok=True)

    if args.retrim_existing:
        _retrim_existing_voices(ffmpeg_bin)
        return

    api_key = cfg.load_env_var("ELEVENLABS_API_KEY", required=True)

    target_langs: tuple[str, ...] = ("en", "es") if args.lang == "all" else (args.lang,)
    active_voices = ensure_custom_voices(api_key, ffmpeg_bin, redesign=args.redesign, langs=target_langs)
    force_voices = bool(args.force or args.force_voices or args.redesign)
    only_speaker = args.only_speaker.strip()

    tasks: list[tuple[str, Any]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        for spec in SFX_SPECS:
            dst_sfx = AUDIO_SFX_DIR / f"{spec['id']}.ogg"
            if not only_speaker or dst_sfx.is_file():
                fut = pool.submit(_generate_one_sfx, api_key, ffmpeg_bin, spec, bool(args.force) and not only_speaker)
                tasks.append((f"sfx:{spec['id']}", fut))

        for line in DIALOGUE_LINES:
            lid = line["id"]
            spk = line["speaker"]
            speaker_match = not only_speaker or spk == only_speaker
            if spk == "v":
                for gender in ("fem", "male"):
                    v_key = f"v_{gender}"
                    for lang, out_dir in (("en", AUDIO_EN_DIR), ("es", AUDIO_ES_DIR)):
                        dst = out_dir / f"{lid}_{gender}.ogg"
                        should_run = (lang in target_langs and speaker_match) or dst.is_file()
                        if not should_run:
                            continue
                        regen = force_voices and lang in target_langs and speaker_match
                        fut = pool.submit(
                            _generate_one_tts,
                            api_key,
                            ffmpeg_bin,
                            active_voices[v_key][lang],
                            lang,
                            line[f"{lang}_tts"],
                            dst,
                            str(line["filter_mode"]),
                            regen,
                            spk,
                        )
                        tasks.append((f"voice:{lid}:{lang}:{gender}", fut))
            else:
                for lang, out_dir in (("en", AUDIO_EN_DIR), ("es", AUDIO_ES_DIR)):
                    dst = out_dir / f"{lid}.ogg"
                    should_run = (lang in target_langs and speaker_match) or dst.is_file()
                    if not should_run:
                        continue
                    regen = force_voices and lang in target_langs and speaker_match
                    fut = pool.submit(
                        _generate_one_tts,
                        api_key,
                        ffmpeg_bin,
                        active_voices[spk][lang],
                        lang,
                        line[f"{lang}_tts"],
                        dst,
                        str(line["filter_mode"]),
                        regen,
                        spk,
                    )
                    tasks.append((f"voice:{lid}:{lang}", fut))

        durations: dict[str, Any] = {"sfx": {}, "voices": {}}
        if DURATIONS_JSON.is_file():
            try:
                old_dur = json.loads(DURATIONS_JSON.read_text(encoding="utf-8"))
                durations["sfx"].update(old_dur.get("sfx", {}))
                for k, v in old_dur.get("voices", {}).items():
                    durations["voices"][k] = dict(v)
            except Exception:
                pass

        for tag, fut in tasks:
            _, sec = fut.result()
            parts = tag.split(":")
            if parts[0] == "sfx":
                durations["sfx"][parts[1]] = sec
            else:
                lid = parts[1]
                lang = parts[2]
                entry = durations["voices"].setdefault(lid, {})
                if len(parts) == 4:
                    entry[f"{lang}_{parts[3]}"] = sec
                else:
                    entry[lang] = sec
            print(f"[OK] {tag} -> {sec:.2f}s")

    for lid, d in durations["voices"].items():
        vals = [float(v) for k, v in d.items() if k != "max"]
        if vals:
            d["max"] = max(vals)

    DURATIONS_JSON.write_text(json.dumps(durations, indent=2, ensure_ascii=False), encoding="utf-8")
    write_audioware_yaml()
    print(f"[DONE] Custom voices   -> {CUSTOM_VOICES_JSON}")
    print(f"[DONE] Audio durations -> {DURATIONS_JSON}")
    print(f"[DONE] Audioware YAML  -> {MANIFEST_YAML}")


if __name__ == "__main__":
    main()
