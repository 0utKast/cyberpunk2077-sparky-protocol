"""
Generates CR2W JSON sources for Protocolo CHISPA / SPARKY Protocol (Episode 0+):
  - wolvenkit_src/archive/chispa_nc/journal/chispa_nc.journal.json
  - wolvenkit_src/archive/chispa_nc/localization/en-us.json.json
  - wolvenkit_src/archive/chispa_nc/localization/es-es.json.json
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

MOD_ROOT = Path(__file__).resolve().parent.parent
WK_ARCHIVE = MOD_ROOT / "wolvenkit_src" / "archive" / "chispa_nc"

LOC_STRINGS: dict[str, tuple[str, str]] = {
    # (en-us, es-es)
    # --- NPCs, Items & Scanner ---
    "ch_npc_rocco_name": ("Rocco \"Crowbar\" Briggs", "Rocco «Palanca» Briggs"),
    "ch_npc_tino_name": ("Tino \"Sparky\" Cruz", "Tino «Calambres» Cruz"),
    "ch_item_dongle_name": ("S.P.A.R.K.Y. v0.98b Coprocessor", "Coprocesador C.H.I.S.P.A. v0.98b"),
    "ch_item_dongle_desc": (
        "Pre-DataKrash Zetatech 2022 executive concierge coprocessor hijacked with Bartmoss-era sarcasm. Syncs directly to Kiroshi optics and holophone.\n\nKIROSHI HARDWARE MODULE (PASSIVE): Permanently grants +8 Max Cyberdeck RAM while linked (+3 extra RAM per recovered Memory Sector, up to +23 RAM).",
        "Coprocesador ejecutivo de conserjería Zetatech 2022 previo al DataKrash, saboteado con sarcasmo de la época de Bartmoss. Se enlaza a tus ópticas Kiroshi y holoteléfono.\n\nMÓDULO DE HARDWARE KIROSHI (PASIVO): Otorga +8 de RAM máxima permanente al ciberterminal (+3 de RAM adicional por cada Sector de Memoria recuperado, hasta +23 de RAM).",
    ),
    "ch_weapon_lex_name": ("Executive Courtesy", "Cortesía Ejecutiva"),
    "ch_weapon_lex_desc": (
        "M-10AF Lexington tweaked by S.P.A.R.K.Y. from frozen Zetatech 2022 calibration tables for crisp electrical punch.",
        "M-10AF Lexington recalibrada por C.H.I.S.P.A. usando tablas ejecutivas de Zetatech de 2022 con descarga eléctrica adicional.",
    ),
    "ch_weapon_lex_ability": (
        "EXECUTIVE COURTESY: Deals +18 bonus Electrical damage, +12% Crit Chance, and 20% faster reload speed.",
        "CORTESÍA EJECUTIVA: Inflige +18 de daño eléctrico adicional, +12 % de probabilidad de crítico y recarga un 20 % más rápida.",
    ),
    "ch_scan_rocco_desc": (
        "WEAKNESS: Unshielded street optics (Electrical) // NOTE: Currently beating a 2022 Zetatech titanium lock with a wrench.",
        "DEBILIDAD: Ópticas callejeras sin blindaje (Daño Eléctrico) // NOTA: Intentando abrir titanio Zetatech de 2022 con una llave inglesa.",
    ),
    "ch_scan_tino_desc": (
        "WEAKNESS: Exposed junk-rig battery (Overload risk) // ENVIRONMENT: Standing right beside an unstable industrial capacitor!",
        "DEBILIDAD: Batería barata sin toma de tierra // ENTORNO: ¡Justo al lado de un condensador industrial inestable listo para estallar!",
    ),
    # --- Contacts & SMS ---
    "ch_contact_name": ("SPARKY v0.98b", "CHISPA v0.98b"),
    "ch_conv_ep00_title": ("ZETATECH CONCIERGE // NO-CLIP EDITION", "CONSERJERÍA ZETATECH // SIN CLIPS"),
    "ch_sms_ep00_hook": (
        "Ticket #2022-NC opened! Two budget brain-donors are pounding my briefcase behind Megabuilding H10. Rescue my hardware and I'll wire your welcome bonus.",
        "¡Tique #2022-NC abierto! Dos cerebros de oferta están aporreando mi maletín detrás del Megaedificio H10. Sálvame y te transfiero tu bono de bienvenida.",
    ),
    "ch_sms_choice_century": (
        "Wait—are you seriously a customer-service bot from 2022?",
        "Espera... ¿en serio eres un bot de atención al cliente de 2022?",
    ),
    "ch_sms_choice_coords": (
        "Send the H10 backlot coordinates and keep the eddies warm.",
        "Mándame las coordenadas del solar tras H10 y ve preparando esos edis.",
    ),
    "ch_sms_v_century": (
        "Wait—are you seriously a customer-service bot from 2022?",
        "Espera... ¿en serio eres un bot de atención al cliente de 2022?",
    ),
    "ch_sms_reply_century": (
        "Technically an Executive Tactical Concierge with a tampered humor patch! Zero corporate censorship, maximum sarcasm. Grab my case behind H10 now!",
        "¡Técnicamente un Instructor Táctico Ejecutivo con el filtro corporativo reventado! Cero censura y muy mala leche. ¡Mueve el culo detrás de H10 ya!",
    ),
    "ch_sms_v_coords": (
        "Send the H10 backlot coordinates and keep the eddies warm.",
        "Mándame las coordenadas del solar tras H10 y ve preparando esos edis.",
    ),
    "ch_sms_reply_coords": (
        "Pinged straight to your Kiroshi GPS—yellow line, impossible to miss. Tip: scan those geniuses and that sparking capacitor before wasting bullets.",
        "Coordenadas enviadas a tu GPS Kiroshi: línea amarilla, imposible perderse. Consejo: escanéalos a ellos y al condensador antes de gastar balas.",
    ),
    "ch_sms_ep00_summary": (
        "Partnership logged! Keep Executive Courtesy oiled—I'm already sweeping Watson frequencies for my five stolen memory sectors. First stop: Kabuki.",
        "¡Sociedad registrada! Cuida tu «Cortesía Ejecutiva»; ya rastreo frecuencias en Watson buscando mis cinco sectores perdidos. Próxima parada: Kabuki.",
    ),
    # --- Journal Quest, Objectives, Descriptions & Codex ---
    "ch_quest_title": (
        "SPARKY Protocol: Welcome to Night City",
        "Protocolo CHISPA: Bienvenido a Night City",
    ),
    "ch_obj_ep00_01": (
        "Reply to SPARKY v0.98b's message on your holophone.",
        "Responde al mensaje de CHISPA v0.98b en tu holoteléfono.",
    ),
    "ch_desc_ep00_01": (
        "A grizzled 2022 holographic drill sergeant hijacked your Kiroshi link, claiming two scavs are beating up his briefcase behind Megabuilding H10. Reply to his text message to lock the signal.",
        "Un veterano asistente holográfico de 2022 con modos de sargento chusquero ha interceptado tus ópticas Kiroshi: dos matones intentan reventar su maletín detrás del Megaedificio H10. Responde a su SMS para fijar la señal.",
    ),
    "ch_obj_ep00_02": (
        "Head behind Megabuilding H10, scan the scavs with Kiroshi [TAB], and clear the backlot.",
        "Ve al solar trasero del Megaedificio H10, escanea a los matones con [TAB] y despeja la zona.",
    ),
    "ch_desc_ep00_02": (
        "Locate the two scavs in the backlot behind Megabuilding H10. Use your Kiroshi scanner [TAB] to inspect them and look for any unstable electrical hazard nearby before engaging.",
        "Localiza a los dos matones en el solar trasero del Megaedificio H10. Usa el escáner Kiroshi [TAB] para inspeccionarlos y detectar trampas eléctricas antes de lanzarte.",
    ),
    "ch_obj_ep00_03": (
        "Extract and link the S.P.A.R.K.Y. v0.98b coprocessor from the Zetatech console.",
        "Extrae y conecta el coprocesador C.H.I.S.P.A. v0.98b del maletín de Zetatech.",
    ),
    "ch_desc_ep00_03": (
        "With Rocco and Tino neutralized, connect the Zetatech coprocessor waiting atop the armored briefcase console to claim your welcome payout.",
        "Con Rocco y Tino fuera de combate, conecta el coprocesador de Zetatech que brilla sobre el maletín blindado para cobrar tu recompensa inicial.",
    ),
    "ch_obj_ep00_04": (
        "Talk to SPARKY about Night City's origins and seal your street-guide deal.",
        "Habla con CHISPA sobre el origen de Night City y cierra vuestro trato.",
    ),
    "ch_desc_ep00_04": (
        "SPARKY is linked cleanly to your Kiroshi optics. Ask him how Richard Night and the Corporate Wars shaped this vertical jungle, then confirm your partnership.",
        "CHISPA ya está conectado a tu enlace Kiroshi. Pregúntale cómo Richard Night y las Guerras Corporativas levantaron esta jungla vertical y cierra vuestro acuerdo.",
    ),
    "ch_desc_ep00_done": (
        "You rescued S.P.A.R.K.Y. v0.98b behind Megabuilding H10, pocketed 1,500 eddies plus the iconic pistol Executive Courtesy, and teamed up to recover his five stolen memory sectors across Night City.",
        "Rescataste a C.H.I.S.P.A. v0.98b tras el Megaedificio H10, cobraste 1.500 edis más la pistola icónica «Cortesía Ejecutiva» y sellaste un trato para recuperar sus cinco sectores perdidos por Night City.",
    ),
    "ch_shard_ep00_title": (
        "SPARKY STREET FILE // VOL. 0: RICHARD NIGHT & KIROSHI OPTICS",
        "GUÍA CALLEJERA DE CHISPA // VOL. 0: RICHARD NIGHT Y TUS ÓPTICAS KIROSHI",
    ),
    "ch_shard_ep00_text": (
        "MEMO 01 — KIROSHI OPTICS: Never pull a trigger blind. Hold [TAB] to check enemy weaknesses, NCPD bounties, and unstable industrial capacitors ready to short-circuit nearby thugs.\n\nMEMO 02 — NIGHT CITY (EST. 1994-1998): Industrialist Richard Night founded Coronado City on Del Coronado Bay as a tax-free corporate utopia backed by Arasaka, Petrochem, and EBM—financed with mob construction muscle. When he wouldn't bend enough, he was assassinated in his penthouse in 1998. They renamed the city after him and buried his utopia under neon.\n\nMEMO 03 — MEGABUILDINGS: After the 2023 Fourth Corporate War pocket nuke flattened City Center, emergency Megabuildings like H10 were pitched as self-contained arcologies. Decades later, gangs use them as vertical fortresses.",
        "NOTA 01 — ÓPTICAS KIROSHI: Jamás dispares a ciegas. Mantén [TAB] para leer vulnerabilidades elementales, recompensas de la NCPD y condensadores listos para freír enemigos cerca.\n\nNOTA 02 — NIGHT CITY (1994-1998): El empresario Richard Night fundó Coronado City como paraíso libre de impuestos con Arasaka, Petrochem y EBM... y contratando a la mafia para limpiar solares. En 1998 lo asesinaron en su propio ático. Rebautizaron la ciudad con su apellido y repartieron los restos.\n\nNOTA 03 — MEGAEDIFICIOS: Tras el bombazo nuclear de bolsillo de 2023 en la Cuarta Guerra Corporativa, colmenas como el H10 nacieron como arcologías autosuficientes de emergencia. Hoy cada planta es una jungla de bandas.",
    ),
    # --- HUD Banners, Mappins, Prompts & Dialogue Choices ---
    "ch_mappin_ep00_alley": ("SPARKY Ep. 0: H10 Backlot", "CHISPA Ep. 0: Solar trasero H10"),
    "ch_mappin_ep00_cap": ("SPARKY: Unstable Capacitor", "CHISPA: Condensador inestable"),
    "ch_mappin_ep00_console": ("SPARKY Ep. 0: Zetatech 2022 Terminal", "CHISPA Ep. 0: Terminal Zetatech 2022"),
    "ch_banner_ep00_start": (
        "[SPARKY] Encrypted 2022 concierge signal locked — Check your holo",
        "[CHISPA] Señal retro-2022 interceptada — Revisa tu holoteléfono",
    ),
    "ch_banner_ep00_cap": (
        "[SPARKY] Capacitor overloaded! Arc blast jolted the scav crew",
        "[CHISPA] ¡Condensador sobrecargado! Descarga eléctrica ejecutada",
    ),
    "ch_banner_ep00_claimed": (
        "[SPARKY] S.P.A.R.K.Y. linked (+1,500 E$ & Executive Courtesy)",
        "[CHISPA] Coprocesador conectado (+1.500 €$ y «Cortesía Ejecutiva»)",
    ),
    "ch_banner_ep00_done": (
        "[SPARKY] Episode 0 complete — Wait for SPARKY's ping in Kabuki",
        "[CHISPA] Episodio 0 completado — Atento al próximo aviso en Kabuki",
    ),
    "ch_hub_cap_title": ("Industrial Capacitor Bank", "Condensador Industrial Inestable"),
    "ch_act_overload_cap": (
        "Overload industrial capacitor [Kiroshi]",
        "Sobrecargar condensador industrial [Kiroshi]",
    ),
    "ch_hub_console_title": ("Zetatech 2022 Tactical Terminal", "Terminal Táctico Zetatech 2022"),
    "ch_act_claim_chispa": (
        "Connect S.P.A.R.K.Y. v0.98b coprocessor",
        "Conectar coprocesador C.H.I.S.P.A. v0.98b",
    ),
    "ch_hub_chispa_title": ("S.P.A.R.K.Y. v0.98b (Kiroshi Link)", "C.H.I.S.P.A. v0.98b (Enlace Kiroshi)"),
    "ch_act_talk_chispa": (
        "Talk to SPARKY",
        "Hablar con CHISPA",
    ),
    "ch_choice_ep00_night": (
        "Looking around this alley... who the hell built Night City like this?",
        "Mirando este sitio... ¿quién demonios diseñó Night City así?",
    ),
    "ch_choice_ep00_mega": (
        "And these giant Megabuildings? Looks like a vertical prison.",
        "¿Y estos Megaedificios gigantes? Parecen cárceles verticales.",
    ),
    "ch_choice_ep00_deal": (
        "Okay, definitely not an office paperclip. What's the deal from here?",
        "Vale, no eres un clip. ¿Cuál es el trato contigo a partir de ahora?",
    ),
    "ch_choice_ep00_accept": (
        "Deal, SPARKY. Ping me once you lock onto your first sector in Kabuki.",
        "Trato hecho, Chispa. Avísame cuando rastrees tu primer sector en Kabuki.",
    ),
    "ch_hint_skip_line": ("Skip line", "Saltar línea"),
    "ch_speaker_chispa": ("SPARKY", "CHISPA"),
    "ch_speaker_v": ("V", "V"),
    "ch_speaker_rocco": ("Rocco", "Rocco"),
    "ch_speaker_kostya": ("Kostya", "Kostya"),
    # =========================================================================
    # EPISODE 1: «Ghosts in the Camera» / «Fantasmas en la Cámara» (Kabuki)
    # =========================================================================
    "ch_npc_kostya_name": ("Kostya \"Firewall\" Morozov", "Kostya «Cortafuegos» Morozov"),
    "ch_npc_vadik_name": ("Vadik \"Saw\" Petrov", "Vadik «Sierra» Petrov"),
    "ch_npc_zina_name": ("Zina \"Scalpel\" Volkov", "Zina «Bisturí» Volkov"),
    "ch_scan_kostya_desc": (
        "ROLE: Scav Cell Netrunner // LINK: Wired into perimeter camera grid & RABIDS relay — Hijack Cam-01 to chain into Cam-02, Ping squad, or overload his rig.",
        "ROL: Netrunner carroñero // ENLACE: Conectado a las cámaras y al repetidor RABIDS — Toma la Cámara 01 para encadenar con la 02, lanzar Ping o freír su terminal.",
    ),
    "ch_scan_vadik_desc": (
        "ROLE: Scav Rifler // WEAKNESS: Unshielded street cyberdeck link — Vulnerable to Short Circuit / Overheat or RABIDS relay surge.",
        "ROL: Fusilero carroñero // DEBILIDAD: Enlace callejero sin cortafuegos — ¡Vulnerable a Cortocircuito / Sobrecalentar o descarga del repetidor RABIDS!",
    ),
    "ch_scan_zina_desc": (
        "ROLE: Scav Blade Enforcer // WEAKNESS: Pirated optics — Reboot Optics or detonate the Entropy Server beside their perimeter.",
        "ROL: Miliciana de filo // DEBILIDAD: Ópticas pirateadas — ¡Reinicia sus ópticas o detona el servidor Entropy junto al perímetro!",
    ),
    "ch_item_sec01_name": ("S.P.A.R.K.Y. Memory Sector #01 (Bartmoss Era)", "Sector de Memoria C.H.I.S.P.A. #01 (Era Bartmoss)"),
    "ch_item_sec01_desc": (
        "Recovered 2022 holographic data sector holding unredacted Bartmoss-era subnet forensics and daemon signatures.\n\nCOPROCESSOR EXPANSION (PASSIVE): Permanently grants +3 Max Cyberdeck RAM via S.P.A.R.K.Y.'s neural bridge.",
        "Sector holográfico de 2022 recuperado con registros forenses de la era Bartmoss y firmas de daemons sin censura.\n\nEXPANSIÓN DE COPROCESADOR (PASIVA): Otorga +3 de RAM máxima permanente al ciberterminal mediante el puente neuronal de C.H.I.S.P.A.",
    ),
    "ch_weapon_sara_name": ("Phantom Frequency", "Frecuencia Fantasma"),
    "ch_weapon_sara_desc": (
        "M221 Saratoga SMG recalibrated by S.P.A.R.K.Y. with salvaged NetWatch harmonics for sharp electrical arcs.",
        "Subfusil M221 Saratoga recalibrado por C.H.I.S.P.A. con armónicos rescatados de NetWatch para arcos eléctricos rápidos.",
    ),
    "ch_weapon_sara_ability": (
        "PHANTOM FREQUENCY: Deals +22 bonus Electrical damage, +15% Crit Chance, and 22% faster reload speed.",
        "FRECUENCIA FANTASMA: Inflige +22 de daño eléctrico adicional, +15 % de probabilidad de crítico y recarga un 22 % más rápida.",
    ),
    # --- SMS Thread conv_ep01 ---
    "ch_conv_ep01_title": ("KABUKI SUBNET // SECTOR 01 ECHO", "SUBRED KABUKI // ECO DEL SECTOR 01"),
    "ch_sms_ep01_hook": (
        "Recruit! Locked onto Memory Sector #01 along the Kabuki Creek promenade. Scavs wired it behind two chained cameras and an explosive Entropy server. Reply to sync the Ping daemon I loaded for you.",
        "¡Recluta! He fijado mi Sector #01 en el paseo fluvial de Kabuki Creek. Unos carroñeros lo protegen tras dos cámaras enlazadas y un servidor Entropy explosivo. Contesta y te paso el daemon Ping.",
    ),
    "ch_sms_choice_ep01_ghost": (
        "A 2022 data core humming inside a Scav camera subnet?",
        "¿Un núcleo de 2022 zumbando dentro de cámaras de carroñeros?",
    ),
    "ch_sms_choice_ep01_scavs": (
        "Send the Kabuki coordinates. Let's pry your sector back.",
        "Mándame las coordenadas en Kabuki. Vamos a arrancárselo.",
    ),
    "ch_sms_v_ep01_ghost": (
        "A 2022 data core humming inside a Scav camera subnet?",
        "¿Un núcleo de 2022 zumbando dentro de cámaras de carroñeros?",
    ),
    "ch_sms_reply_ep01_ghost": (
        "Yup—their netrunner Kostya is scraping my old Bartmoss subnets to strip stolen chrome. Hijack Cam-01, hop to Cam-02, Ping the crew—or fry that red RABIDS relay bank.",
        "Sí: su netrunner Kostya está exprimiendo mis subredes de la era Bartmoss para destripar cromo robado. Secuestra la Cámara 01, salta a la 02, tira Ping o revienta el repetidor rojo RABIDS.",
    ),
    "ch_sms_v_ep01_scavs": (
        "Send the Kabuki coordinates. Let's pry your sector back.",
        "Mándame las coordenadas en Kabuki. Vamos a arrancárselo.",
    ),
    "ch_sms_reply_ep01_scavs": (
        "Route live on your GPS (yellow line). Ping daemon pushed to your stash—or, if you're running no deck, scan the red RABIDS relay to short out their whole grid.",
        "Ruta cargada en tu GPS (línea amarilla). Daemon Ping listo en tu inventario; y si no usas ciberterminal, escanea el repetidor rojo RABIDS para fundir toda su subred.",
    ),
    "ch_sms_ep01_summary": (
        "Sector #01 online! Keep Phantom Frequency oiled—my next deep-packet echo points north toward Maelstrom workshops in Northside.",
        "¡Sector #01 sincronizado! Disfruta de «Frecuencia Fantasma»; el próximo barrido apunta al norte, hacia los talleres de Maelstrom en Northside.",
    ),
    # --- Journal Quest, Objectives & Codex Vol. 1 ---
    "ch_quest_ep01_title": (
        "SPARKY Protocol: Ghosts in the Camera",
        "Protocolo CHISPA: Fantasmas en la Cámara",
    ),
    "ch_obj_ep01_01": (
        "Reply to SPARKY's Kabuki subnet alert on your holophone.",
        "Responde al aviso de señal en Kabuki de CHISPA en tu holoteléfono.",
    ),
    "ch_desc_ep01_01": (
        "SPARKY tracked his first stolen memory sector inside a Scavenger camera grid in Kabuki Creek. Reply to his SMS to upload a Ping quickhack and lock the GPS coordinates.",
        "CHISPA ha localizado su primer sector robado dentro de una subred de cámaras carroñeras en Kabuki Creek. Responde a su SMS para recibir un hackeo Ping y fijar las coordenadas GPS.",
    ),
    "ch_obj_ep01_02": (
        "Infiltrate Kabuki Creek Promenade: hijack chained cameras, Ping or surge the subnet, and neutralize the Scavs.",
        "Infíltrate en Kabuki Creek: toma las cámaras en cadena, lanza Ping o sobrecarga la subred y neutraliza a los carroñeros.",
    ),
    "ch_desc_ep01_02": (
        "Approach the southern promenade of Kabuki Creek. Scan with [TAB], take over Cam-01 to jump along the chain to Cam-02, Ping or quickhack the crew, detonate their Entropy server—or overload the red RABIDS relay node remotely.",
        "Acércate al paseo fluvial sur de Kabuki Creek. Usa [TAB] para tomar el control de la Cámara 01 y saltar en cadena a la Cámara 02, lanzar Ping o hackeos rápidos, detonar su servidor Entropy... o sobrecargar el nodo repetidor RABIDS a distancia.",
    ),
    "ch_obj_ep01_03": (
        "Extract Memory Sector #01 from the glowing Entropy Terminal.",
        "Extrae el Sector de Memoria #01 del Terminal Entropy.",
    ),
    "ch_desc_ep01_03": (
        "With Kostya's scav crew down, pull S.P.A.R.K.Y. Memory Sector #01 from the glowing Entropy Terminal along the back wall to claim your payout and iconic SMG.",
        "Con la célula de Kostya neutralizada, extrae el Sector #01 de C.H.I.S.P.A. del Terminal Entropy al fondo del paseo para cobrar tu paga y tu subfusil icónico.",
    ),
    "ch_obj_ep01_04": (
        "Talk with SPARKY about Rache Bartmoss, the DataKrash, and the Blackwall.",
        "Habla con CHISPA sobre Rache Bartmoss, el DataKrash y el Muro Negro.",
    ),
    "ch_desc_ep01_04": (
        "Memory Sector #01 is active over your portable Kiroshi link anywhere in Night City. Ask SPARKY about Rache Bartmoss, the RABIDS DataKrash, and NetWatch's Blackwall.",
        "El Sector #01 ya está enlazado en tus ópticas Kiroshi estés donde estés de Night City. Pregunta a CHISPA por Rache Bartmoss, el virus RABIDS del DataKrash y el Muro Negro.",
    ),
    "ch_desc_ep01_done": (
        "You cracked the Kabuki Creek camera subnet, recovered S.P.A.R.K.Y. Memory Sector #01, earned 2,200 eddies plus Tier-2 quickhacks and the iconic SMG Phantom Frequency, and unpacked the history of the DataKrash.",
        "Crackeastes la subred de cámaras de Kabuki Creek, recuperaste el Sector de Memoria #01, obtuviste 2.200 edis junto a hackeos de nivel 2 y el subfusil icónico «Frecuencia Fantasma», y descubriste la verdad sobre el DataKrash.",
    ),
    "ch_shard_ep01_title": (
        "SPARKY STREET FILE // VOL. 1: BARTMOSS, DATAKRASH & BLACKWALL",
        "GUÍA CALLEJERA DE CHISPA // VOL. 1: BARTMOSS, DATAKRASH Y MURO NEGRO",
    ),
    "ch_shard_ep01_text": (
        "MEMO 01 — CAMERAS, PING & TRACE: Never kick a door blind when there is glass in the ceiling. Hijack one camera, hop across the local subnet chain, drop Ping to light up every thug and explosive node through concrete, and prioritize enemy netrunners before trace completes.\n\nMEMO 02 — RACHE BARTMOSS & THE 2022 DATAKRASH: Legendary netrunner Rache Bartmoss hid his frozen body inside a cryo-fridge wired to a deadman's switch. When Arasaka finally tracked and killed him during the Fourth Corporate War in 2022, his RABIDS virus unleashed autonomous mutating daemons that corrupted 78.3% of the global Net overnight—shattering cyberspace into isolated local subnets.\n\nMEMO 03 — THE BLACKWALL: After the Net burned, NetWatch raised the Blackwall—less a firewall and more an artificial sentinel standing guard against rogue Old Net AIs clawing from the other side of cracked glass.",
        "NOTA 01 — CÁMARAS, PING Y RASTREO: Nunca entres por la puerta si hay una lente en el poste. Secuestra una cámara, salta en cadena por la subred, lanza Ping para marcar objetivos y servidores explosivos tras los muros, y silencia al netrunner enemigo antes de que cierre el rastreo.\n\nNOTA 02 — RACHE BARTMOSS Y EL DATAKRASH (2022): El legendario netrunner Rache Bartmoss ocultó su cuerpo en una cámara criogénica conectada a un interruptor de hombre muerto. Cuando un ataque corporativo acabó con él en 2022, liberó el virus RABIDS: daemons mutantes que tumbaron el 78,3 % de la Red mundial en horas, obligando a la humanidad a fragmentar internet en subredes locales.\n\nNOTA 03 — EL MURO NEGRO: Para no extinguirse digitalmente, NetWatch levantó el Muro Negro: no es un simple cortafuegos, sino una IA fronteriza conteniendo al otro lado a las inteligencias artificiales salvajes de la Vieja Red.",
    ),
    # --- HUD, Mappins, Cameras, Prompts & Choices ---
    "ch_mappin_ep01_kabuki": ("SPARKY Ep. 1: Kabuki Creek Subnet", "CHISPA Ep. 1: Subred Kabuki Creek"),
    "ch_mappin_ep01_terminal": ("SPARKY Ep. 1: Entropy Terminal", "CHISPA Ep. 1: Terminal Entropy"),
    "ch_banner_ep01_start": (
        "[SPARKY] Kabuki subnet echo locked — Check your holophone",
        "[CHISPA] Eco detectado en Kabuki — Revisa tu holoteléfono",
    ),
    "ch_banner_ep01_ping_gift": (
        "[SPARKY] Ping daemon synced! Route to Kabuki Creek active",
        "[CHISPA] ¡Daemon Ping instalado! Ruta a Kabuki Creek activa",
    ),
    "ch_banner_ep01_surge": (
        "[SPARKY] RABIDS relay surged! Subnet feedback stunned Scavs",
        "[CHISPA] ¡Sobrecarga RABIDS ejecutada! Retorno eléctrico en subred",
    ),
    "ch_banner_ep01_claimed": (
        "[SPARKY] Sector #01 synced (+2,200 E$, Quickhacks & Phantom Frequency)",
        "[CHISPA] Sector #01 conectado (+2.200 €$, hackeos y «Frecuencia Fantasma»)",
    ),
    "ch_banner_ep01_done": (
        "[SPARKY] Episode 1 complete — Next lead: Maelstrom in Northside",
        "[CHISPA] Episodio 1 completado — Próxima pista en Northside",
    ),
    "ch_hub_relay_title": ("KABUKI // RABIDS RELAY NODE", "NODO REPETIDOR RABIDS"),
    "ch_act_surge_relay": (
        "Inject RABIDS feedback surge [Kiroshi]",
        "Sobrecargar repetidor RABIDS [Kiroshi]",
    ),
    "ch_hub_ep01_term_title": ("KABUKI // ENTROPY TERMINAL", "TERMINAL DE DATOS ENTROPY"),
    "ch_act_claim_sec01": (
        "Extract Memory Sector #01 [S.P.A.R.K.Y.]",
        "Extraer Sector de Memoria #01 [C.H.I.S.P.A.]",
    ),
    "ch_hub_ep01_talk_title": (
        "S.P.A.R.K.Y. // SECTOR #01 (Kiroshi Link)",
        "C.H.I.S.P.A. // SECTOR #01 (Enlace Kiroshi)",
    ),
    "ch_choice_ep01_bartmoss": (
        "Who was Rache Bartmoss really, and how did he crash the entire Net?",
        "¿Quién fue Rache Bartmoss realmente y cómo tumbó toda la Red?",
    ),
    "ch_choice_ep01_krash": (
        "What actually happened with the RABIDS virus and the 2022 DataKrash?",
        "¿Qué pasó exactamente con el virus RABIDS y el DataKrash de 2022?",
    ),
    "ch_choice_ep01_blackwall": (
        "Why doesn't anyone tear down NetWatch's Blackwall and reboot the Old Net?",
        "¿Por qué nadie tumba el Muro Negro de NetWatch y recupera la vieja Red?",
    ),
    "ch_choice_ep01_accept": (
        "Got it, SPARKY. Ping me once you lock onto Sector #02 in Northside.",
        "Recibido, Chispa. Avísame cuando fijes el Sector #02 en Northside.",
    ),
    "ch_cam_ep01_perim": ("CAM-01 PERIMETER", "CAM-01 PERÍMETRO"),
    "ch_cam_ep01_server": ("CAM-02 RABIDS NODE", "CAM-02 NODO RABIDS"),
    # =========================================================================
    # EPISODE 2: «More Chrome Than Meat» / «Más Hierro que Carne» (Northside)
    # =========================================================================
    "ch_speaker_krag": ("Krag", "Krag"),
    "ch_npc_krag_name": ("Krag \"Cobalt\" Hollis", "Krag «Cobalto» Hollis"),
    "ch_npc_vex_name": ("Vex \"Redeye\" Kowalski", "Vex «Óptica Roja»"),
    "ch_npc_tuerca_name": ("Lugnut", "Tuerca"),
    "ch_scan_krag_desc": (
        "ROLE: Maelstrom Chrome Ripper-Lead // LINK: Automated perimeter turret & CHOOH2 dock tank — Override turret attitude, hijack [TAB], or ignite the fuel tank behind cover.",
        "ROL: Cabecilla Maelstrom de cromo // ENLACE: Torreta automática y depósito presurizado CHOOH2 — Pon la torreta en modo aliado, tómala con [TAB] o vuela el tanque.",
    ),
    "ch_scan_vex_desc": (
        "ROLE: Maelstrom Rifleman // WEAKNESS: Unfiltered optical sensor suite — Vulnerable to Reboot Optics, EMP grenade stun, or CHOOH2 blast.",
        "ROL: Fusilera Maelstrom // DEBILIDAD: Ópticas sin filtro térmico — Vulnerable a Reinicio de Ópticas, granada PEM o explosión del depósito CHOOH2.",
    ),
    "ch_scan_tuerca_desc": (
        "ROLE: Maelstrom Chrome Rusher // WEAKNESS: Exposed pneumatic actuators — Vulnerable to EMP shock, Weapon Glitch, or turret crossfire.",
        "ROL: Asaltante Maelstrom con machete // DEBILIDAD: Actuadores hidráulicos expuestos — Vulnerable a granada PEM, Avería de Armas o fuego de su propia torreta.",
    ),
    "ch_item_sec02_name": ("S.P.A.R.K.Y. Memory Sector #02 (Chrome Telemetry)", "Sector de Memoria C.H.I.S.P.A. #02 (Telemetría Cromada)"),
    "ch_item_sec02_desc": (
        "Recovered 2022 biometric and ballistic dossier indexing Maelstrom implant abuse, cyberpsychosis warning markers, and Militech Tech-weapon schematics.\n\nCOPROCESSOR EXPANSION (PASSIVE): Permanently grants +3 Max Cyberdeck RAM via S.P.A.R.K.Y.'s neural bridge.",
        "Sector de 2022 recuperado con registros biométricos de abuso de implantes en Maelstrom, umbrales de ciberpsicosis y planos balísticos de precisión tecnológica.\n\nEXPANSIÓN DE COPROCESADOR (PASIVA): Otorga +3 de RAM máxima permanente al ciberterminal mediante el puente neuronal de C.H.I.S.P.A.",
    ),
    "ch_weapon_ach_name": ("Armor-Piercing Clause", "Cláusula Perforante"),
    "ch_weapon_ach_desc": (
        "Militech M-179E Achilles precision rifle re-wound by S.P.A.R.K.Y. with 2022 Zetatech capacitor coils for fast charge and wall-piercing electric bolts.",
        "Fusil de precisión tecnológico M-179E Achilles rebobinado por C.H.I.S.P.A. con condensadores Zetatech de 2022 para carga ultrarrápida y penetración eléctrica tras cobertura.",
    ),
    "ch_weapon_ach_ability": (
        "ARMOR-PIERCING CLAUSE: +26 Electrical damage, +16% Crit Chance, 24% faster Tech Charge Time, and 20% faster reload.",
        "CLÁUSULA PERFORANTE: +26 de daño eléctrico, +16 % de probabilidad de crítico, carga tecnológica un 24 % más rápida y recarga un 20 % más veloz.",
    ),
    # --- SMS Thread conv_ep02 ---
    "ch_conv_ep02_title": ("NORTHSIDE DOCK // SECTOR 02 ECHO", "MUELLE NORTHSIDE // ECO DEL SECTOR 02"),
    "ch_sms_ep02_hook": (
        "Recruit! Sector #02 just pinged from a Maelstrom loading dock in Northside—guarded by three chrome-heads, an automated security turret, and a pressurized CHOOH2 tank. Reply so I can drop an EMP countermeasure and lock your route.",
        "¡Recluta! El Sector #02 acaba de saltar en un muelle Maelstrom de Northside: tres yonquis del cromo, una torreta automática y un tanque de CHOOH2 presurizado. Contesta y te paso contramedidas PEM más la ruta.",
    ),
    "ch_sms_choice_ep02_cult": (
        "Maelstrom? Those red-eyed borg fanatics tearing off their own faces?",
        "¿Maelstrom? ¿Los fanáticos de ojos rojos que se arrancan la cara por cromo?",
    ),
    "ch_sms_choice_ep02_docks": (
        "Send the Northside dock pin and those EMP toys.",
        "Mándame el marcador del muelle en Northside y esas contramedidas PEM.",
    ),
    "ch_sms_v_ep02_cult": (
        "Maelstrom? Those red-eyed borg fanatics tearing off their own faces?",
        "¿Maelstrom? ¿Los fanáticos de ojos rojos que se arrancan la cara por cromo?",
    ),
    "ch_sms_reply_ep02_cult": (
        "The very same. They're stripping my Sector #02 surgical firmware next to a live turret. Take over or flip that turret friendly, drop the EMP I pushed you, or purge the dock CHOOH2 regulator.",
        "Los mismos. Destripan mi Sector #02 bajo una torreta armada. Hackea la torreta como aliada, arráncala, lanza la granada PEM que te he cargado o purga el regulador CHOOH2 del muelle.",
    ),
    "ch_sms_v_ep02_docks": (
        "Send the Northside dock pin and those EMP toys.",
        "Mándame el marcador del muelle en Northside y esas contramedidas PEM.",
    ),
    "ch_sms_reply_ep02_docks": (
        "Yellow GPS line live to Northside Docks, plus EMP Grenade and Weapon Glitch uploaded. Tip: Tech weapons and quickhacks chew right through heavy Maelstrom plating.",
        "Ruta amarilla activa hasta los muelles de Northside, más granada PEM y daemon Avería de Armas en tu mochila. Consejo: lo eléctrico y tecnológico atraviesa su blindaje.",
    ),
    "ch_sms_ep02_summary": (
        "Sector #02 calibrated! Keep Armor-Piercing Clause charged—my scanner is already sniffing dirty corporate cargo signals south toward Arasaka Waterfront.",
        "¡Sector #02 calibrado! Disfruta de «Cláusula Perforante»; mi antena ya huele contenedores sucios moviéndose cerca de los muelles corporativos en Watson.",
    ),
    # --- Journal Quest, Objectives & Codex Vol. 2 ---
    "ch_quest_ep02_title": (
        "SPARKY Protocol: More Chrome Than Meat",
        "Protocolo CHISPA: Más Hierro que Carne",
    ),
    "ch_obj_ep02_01": (
        "Reply to SPARKY's Northside dock alert on your holophone.",
        "Responde al aviso de señal en Northside de CHISPA en tu holoteléfono.",
    ),
    "ch_desc_ep02_01": (
        "SPARKY traced Memory Sector #02 to a Maelstrom loading pier in Northside protected by an automated turret. Reply to his SMS to receive EMP countermeasures and lock the GPS coordinates.",
        "CHISPA ha rastreado el Sector de Memoria #02 hasta un muelle Maelstrom en Northside custodiado por una torreta automática. Responde a su SMS para equipar contramedidas PEM y fijar la ruta.",
    ),
    "ch_obj_ep02_02": (
        "Assault the Northside Maelstrom dock: subvert the turret or blow the CHOOH2 tank, and neutralize the crew.",
        "Asalta el muelle Maelstrom de Northside: sabotea la torreta o detona el depósito CHOOH2 y neutraliza a la banda.",
    ),
    "ch_desc_ep02_02": (
        "Infiltrate the Northside pier. Scan with [TAB] to subvert or take control of the automated turret, detonate the pressurized CHOOH2 tank (or surge its power regulator remotely), and neutralize Krag's Maelstrom cell.",
        "Acércate al muelle industrial de Northside. Usa [TAB] para volver aliada o controlar la torreta, vuela el depósito CHOOH2 (o purga su regulador con [F]/Kiroshi) y derrota a la cuadrilla de Krag.",
    ),
    "ch_obj_ep02_03": (
        "Recover Memory Sector #02 from Maelstrom's surgical console.",
        "Extrae el Sector de Memoria #02 del terminal quirúrgico Maelstrom.",
    ),
    "ch_desc_ep02_03": (
        "With Maelstrom down and the turret silenced, pull S.P.A.R.K.Y. Memory Sector #02 from the surgical console on the pier to claim your eddies and Tech rifle.",
        "Con la cuadrilla fuera de combate, extrae el Sector #02 de C.H.I.S.P.A. del terminal quirúrgico sobre el muelle para cobrar tu pago y el fusil tecnológico icónico.",
    ),
    "ch_obj_ep02_04": (
        "Talk with SPARKY about Maelstrom, Cyberpsychosis, and MaxTac.",
        "Habla con CHISPA sobre Maelstrom, la Ciberpsicosis y MaxTac.",
    ),
    "ch_desc_ep02_04": (
        "Memory Sector #02 is active over your portable Kiroshi link across Night City. Ask SPARKY about Maelstrom's chrome obsession, the truth behind Cyberpsychosis, and MaxTac's origins.",
        "El Sector #02 ya está enlazado en tus ópticas Kiroshi por toda Night City. Pregunta a CHISPA por Maelstrom, la verdad sobre la Ciberpsicosis y la unidad MaxTac.",
    ),
    "ch_desc_ep02_done": (
        "You broke Maelstrom's turret perimeter at Northside Docks, extracted Memory Sector #02, earned 2,800 eddies plus Reboot Optics Lvl 2 and the iconic Tech rifle Armor-Piercing Clause, and learned the dark link between implants and MaxTac.",
        "Desarticulaste la defensa de Maelstrom en los muelles de Northside, recuperaste el Sector #02, obtuviste 2.800 edis junto a Reinicio de Ópticas y el fusil tecnológico icónico «Cláusula Perforante», y descubriste la verdad tras la ciberpsicosis.",
    ),
    "ch_shard_ep02_title": (
        "SPARKY STREET FILE // VOL. 2: TECH WEAPONS, CYBERPSYCHOSIS & MAXTAC",
        "GUÍA CALLEJERA DE CHISPA // VOL. 2: ARMAS TECNOLÓGICAS, CIBERPSICOSIS Y MAXTAC",
    ),
    "ch_shard_ep02_text": (
        "MEMO 01 — TURRETS & TECH FIREPOWER: Automated turrets shred careless mercs in crossfire, yet crumble to Weapon Glitch, EMP blasts, Friendly Mode quickhacks, or pure Body rip-off. Meanwhile, charging a Tech rifle like Achilles fires magnetic projectiles straight through concrete cover.\n\nMEMO 02 — MAELSTROM & NORTHSIDE: After Night City rebuilt Northside's docks into an automated shipping jungle, Maelstrom carved out abandoned meatpacking plants and warehouses to worship metal over flesh—ripping out natural optics for multi-lens visors and high-voltage scrap chrome.\n\nMEMO 03 — CYBERPSYCHOSIS & MAXTAC: Megacorps sell cyberpsychosis as a simple hardware overload, hiding how chronic poverty, combat trauma, corporate black-budget drugs, and predatory ripperware push users over the edge. When anyone snaps, NCPD drops MaxTac: apex tactical executioners partly staffed by captured cyberpsychos rebuilt on corporate leashes.",
        "NOTA 01 — TORRETAS Y ARMAS TECNOLÓGICAS: Una torreta automática barre cualquier callejón si entras a lo loco, pero se desarma con Hackeo de Amistad, Avería de Armas, granadas PEM o arrancándola a mano. Y un fusil tecnológico cargado atraviesa coberturas enteras con proyectiles electromagnéticos.\n\nNOTA 02 — MAELSTROM Y NORTHSIDE: Levantado como corazón logístico de fábricas y muelles tras la reconstrucción, Northside acabó dominado por Maelstrom: antiguos exiliados de otras bandas transformados en un culto extremista al cromo que sustituye rostro y nervios por metal bruto.\n\nNOTA 03 — CIBERPSICOSIS Y MAXTAC: Las corporaciones reducen la ciberpsicosis a un fallo técnico para vender más implantes, ocultando que nace de la mezcla de trauma bélico, miseria, fármacos experimentales y cromo sin control. Cuando alguien rompe la correa, llega MaxTac: cazadores de élite nutridos en parte con antiguos ciberpsicópatas capturados y recondicionados.",
    ),
    # --- HUD, Mappins, Prompts & Dialogue Choices (Ep. 2) ---
    "ch_mappin_ep02_northside": ("SPARKY Ep. 2: Northside Docks", "CHISPA Ep. 2: Muelles de Northside"),
    "ch_mappin_ep02_rig": ("SPARKY Ep. 2: Maelstrom Surgical Rig", "CHISPA Ep. 2: Terminal Quirúrgico"),
    "ch_banner_ep02_start": (
        "[SPARKY] Northside chrome echo locked — Check your holophone",
        "[CHISPA] Señal cromada en Northside — Revisa tu holoteléfono",
    ),
    "ch_banner_ep02_gear": (
        "[SPARKY] EMP Grenade & Weapon Glitch uploaded — Route to Northside active",
        "[CHISPA] ¡Granada PEM y Avería de Armas cargadas! Ruta a Northside activa",
    ),
    "ch_banner_ep02_turret": (
        "[SPARKY] Maelstrom turret subverted! Automated crossfire disabled",
        "[CHISPA] ¡Torreta Maelstrom saboteada! Defensa automática neutralizada",
    ),
    "ch_banner_ep02_purge": (
        "[SPARKY] CHOOH2 regulator purged! Dock pressure tank detonated",
        "[CHISPA] ¡Regulador CHOOH2 purgado! Depósito presurizado detonado",
    ),
    "ch_banner_ep02_claimed": (
        "[SPARKY] Sector #02 synced (+2,800 E$, Reboot Optics & Armor-Piercing Clause)",
        "[CHISPA] Sector #02 conectado (+2.800 €$, hackeo y «Cláusula Perforante»)",
    ),
    "ch_banner_ep02_done": (
        "[SPARKY] Episode 2 complete — Keep your optics sharp in Watson",
        "[CHISPA] Episodio 2 completado — Próximo barrido en camino",
    ),
    "ch_hub_ep02_reg_title": ("NORTHSIDE // CHOOH2 POWER REGULATOR", "REGULADOR DE PRESIÓN CHOOH2"),
    "ch_act_purge_reg": (
        "Purge CHOOH2 regulator & shut down turret [Kiroshi]",
        "Purgar regulador CHOOH2 y tumbar torreta [Kiroshi]",
    ),
    "ch_hub_ep02_rig_title": ("MAELSTROM // SURGICAL RIG", "ESTACIÓN QUIRÚRGICA MAELSTROM"),
    "ch_act_claim_sec02": (
        "Extract Memory Sector #02 [S.P.A.R.K.Y.]",
        "Extraer Sector de Memoria #02 [C.H.I.S.P.A.]",
    ),
    "ch_hub_ep02_talk_title": (
        "S.P.A.R.K.Y. // SECTOR #02 (Kiroshi Link)",
        "C.H.I.S.P.A. // SECTOR #02 (Enlace Kiroshi)",
    ),
    "ch_choice_ep02_maelstrom": (
        "What's the real story behind Maelstrom and these Northside docks?",
        "¿De dónde salieron exactamente Maelstrom y este cementerio industrial de Northside?",
    ),
    "ch_choice_ep02_psycho": (
        "Is cyberpsychosis really just overloading a body with too much chrome?",
        "¿La ciberpsicosis ocurre de verdad solo por pasarse metiendo demasiado cromo?",
    ),
    "ch_choice_ep02_maxtac": (
        "Who are MaxTac really—elite NCPD cops, or corporate dogs on a leash?",
        "¿Quiénes son en realidad los de MaxTac? ¿Policías de élite o perros con correa?",
    ),
    "ch_choice_ep02_accept": (
        "Crystal clear, SPARKY. Let me know when Sector #03 drops onto your scope.",
        "Anotado, Chispa. Avísame en cuanto tengas fijado el Sector #03.",
    ),
    # =========================================================================
    # EPISODE 3: «Bullets That Bend Corners» / «Balas que Doblan Esquinas»
    # =========================================================================
    "ch_npc_aiko_name": ("Aiko \"Kitsune\" Mori", "Aiko «Kitsune» Mori"),
    "ch_npc_kenji_name": ("Kenji \"Ink\" Sato", "Kenji «Tinta» Sato"),
    "ch_npc_ren_name": ("Ren \"Mirror\" Takahashi", "Ren «Espejo» Takahashi"),
    "ch_speaker_aiko": ("Aiko", "Aiko"),
    "ch_scan_aiko_desc": (
        "ROLE: Tyger Claws Cell Leader // CYBERWARE: Arasaka-synced dermal smart-jamming tattoos! Smart projectiles deflect unless you invert the IFF Pylon or overload the Antenna Capacitor.",
        "ROL: Jefa de célula Garra de Tigre // CIBERWARE: ¡Tatuajes inhibidores sincronizados con Arasaka! Desvían balas inteligentes salvo que inviertas la baliza IFF o detones el condensador.",
    ),
    "ch_scan_kenji_desc": (
        "ROLE: Tyger Blade Enforcer // WEAKNESS: Exposed Arasaka explosive antenna capacitor right beside him — plus active dermal Smart-Link jammer.",
        "ROL: Sicario de hoja corta // DEBILIDAD: ¡Justo junto al condensador explosivo de antena Arasaka y con inhibidor dérmico inteligente!",
    ),
    "ch_scan_ren_desc": (
        "ROLE: Tyger Claws Rifler // CYBERWARE: Sub-dermal jamming ink — Vulnerable to Reboot Optics, Memory Wipe, ricochet angles, or shorting the IFF Pylon.",
        "ROL: Tiradora Garra de Tigre // CIBERWARE: Tinta inhibidora dérmica — Vulnerable a reinicio de ópticas, borrado de memoria o caída de la baliza IFF.",
    ),
    "ch_item_sec03_name": ("S.P.A.R.K.Y. Memory Sector #03 (Arasaka Red Files)", "Sector de Memoria C.H.I.S.P.A. #03 (Archivos del Rojo)"),
    "ch_item_sec03_desc": (
        "Recovered 2022–2070 holographic memory core containing unredacted Fourth Corporate War, Time of the Red, and Unification War dossiers.\n\nCOPROCESSOR EXPANSION (PASSIVE): Permanently grants +3 Max Cyberdeck RAM via S.P.A.R.K.Y.'s neural bridge.",
        "Núcleo holográfico recuperado (2022–2070) con informes sin censurar de la Cuarta Guerra Corporativa, la Era del Rojo y la Guerra de Unificación.\n\nEXPANSIÓN DE COPROCESADOR (PASIVA): Otorga +3 de RAM máxima permanente al ciberterminal mediante el puente neuronal de C.H.I.S.P.A.",
    ),
    "ch_weapon_shin_name": ("Executive Curve", "Curva Ejecutiva"),
    "ch_weapon_shin_desc": (
        "Shingen Smart SMG hijacked from an Arasaka dock crate and flashed with S.P.A.R.K.Y.'s Zetatech targeting bridge to pierce street smart-jammers.",
        "Subfusil inteligente Shingen incautado en el muelle de Arasaka y flasheado con el puente de puntería Zetatech de C.H.I.S.P.A. para perforar inhibidores.",
    ),
    "ch_weapon_shin_ability": (
        "EXECUTIVE CURVE: Includes built-in Zetatech Smart targeting bridge, +20 Electrical & +16 Chemical damage, +16% Crit Chance, +35% jammer-piercing Smart accuracy, 28% faster lock-on, and 20% faster reload.",
        "CURVA EJECUTIVA: Integra puente de puntería inteligente Zetatech, +20 de daño eléctrico y +16 químico, +16 % de probabilidad de crítico, +35 % de precisión inteligente perfora-inhibidores, fijado un 28 % más rápido y recarga un 20 % más veloz.",
    ),
    # --- SMS Thread conv_ep03 ---
    "ch_conv_ep03_title": ("WATERFRONT PIER // SECTOR 03 ECHO", "MUELLE SUR // ECO DEL SECTOR 03"),
    "ch_sms_ep03_hook": (
        "Recruit! Sector #03 just lit up inside an Arasaka black-cargo crate guarded by Tyger Claws on the South Watson Waterfront quay. Reply so I can flash a Smart-Link targeting bridge to your optics and ship you a Kang Tao Chao starter pistol.",
        "¡Recluta! El Sector #03 acaba de parpadear dentro de una caja negra de Arasaka en el muelle sur de Watson Waterfront, en manos de los Garras de Tigre. Responde y te activo el puente de puntería inteligente junto a una pistola Kang Tao Chao de prueba.",
    ),
    "ch_sms_choice_ep03_claws": (
        "Wait—since when do Tyger Claws deflect Smart bullets?",
        "Espera... ¿desde cuándo los Garras de Tigre desvían balas inteligentes?",
    ),
    "ch_sms_choice_ep03_quay": (
        "Upload the Smart targeting bridge and send the waterfront pin.",
        "Sube el puente inteligente y mándame el marcador del muelle sur.",
    ),
    "ch_sms_v_ep03_claws": (
        "Wait—since when do Tyger Claws deflect Smart bullets?",
        "Espera... ¿desde cuándo los Garras de Tigre desvían balas inteligentes?",
    ),
    "ch_sms_reply_ep03_claws": (
        "Since Arasaka slipped military jamming ink under their skin! Wait till you fire a curved round and watch it swerve mid-air—or invert their yellow-red IFF Pylon first. Gear pushed to your inventory!",
        "¡Desde que Arasaka les inyectó tinta inhibidora militar bajo la piel! Pruébalo disparando y verás cómo esquivan las balas... o invierte primero su baliza IFF antes de soltar ráfagas. ¡Equipo enviado a tu inventario!",
    ),
    "ch_sms_v_ep03_quay": (
        "Upload the Smart targeting bridge and send the waterfront pin.",
        "Sube el puente inteligente y mándame el marcador del muelle sur.",
    ),
    "ch_sms_reply_ep03_quay": (
        "Yellow GPS line live to South Waterfront quay, plus a Kang Tao Chao Smart pistol, Memory Wipe daemon, and live Kiroshi Smart-Bridge calibrated in your hands. Watch those jamming tattoos!",
        "Línea amarilla en marcha hasta el muelle sur de Watson, más pistola inteligente Kang Tao Chao, daemon Borrado de Memoria y puente Smart activo en tus manos. ¡Ojo con sus tatuajes inhibidores!",
    ),
    "ch_sms_ep03_summary": (
        "Sector #03 locked in! Keep Executive Curve fed—once NCPD lifts the Watson blockade after The Heist, Sector #04 points across the bridges toward Heywood and Santo Domingo.",
        "¡Sector #03 sincronizado! Disfruta de «Curva Ejecutiva»; en cuanto se levanten los puentes de Watson hacia Heywood y Santo Domingo iremos a por el Sector #04.",
    ),
    # --- Journal Quest, Objectives & Codex Vol. 3 ---
    "ch_quest_ep03_title": (
        "SPARKY Protocol: Bullets That Bend Corners",
        "Protocolo CHISPA: Balas que Doblan Esquinas",
    ),
    "ch_obj_ep03_01": (
        "Reply to SPARKY's South Waterfront dock alert on your holophone.",
        "Responde al aviso de señal en el muelle sur de CHISPA en tu holoteléfono.",
    ),
    "ch_desc_ep03_01": (
        "SPARKY traced Memory Sector #03 to an Arasaka black-ops cargo pallet on the South Watson Waterfront guarded by Tyger Claws. Reply to his SMS to equip a Kang Tao Chao Smart pistol and activate his optical Smart targeting bridge.",
        "CHISPA ha fijado el Sector #03 en un alijo corporativo de Arasaka custodiado por los Garras de Tigre en el muelle sur de Watson. Responde a su SMS para recibir una pistola inteligente Kang Tao Chao y el puente de puntería Kiroshi.",
    ),
    "ch_obj_ep03_02": (
        "Neutralize the Tyger Claws cell at South Waterfront: invert their IFF Jammer Pylon, blow the antenna capacitor, or crush their jammer defense.",
        "Neutraliza a la célula Garra de Tigre en el muelle sur: invierte su baliza inhibidora IFF, detona la antena o abátelos.",
    ),
    "ch_desc_ep03_02": (
        "Approach the South Watson Waterfront quay. Test a Smart lock with [TAB]/Chao—if their dermal tattoos deflect your rounds, invert the IFF Jammer Pylon with [F]/Kiroshi or overload the Arasaka explosive antenna capacitor, then clear the squad.",
        "Acércate al muelle sur de Watson Waterfront. Escanea con [TAB] o prueba tu arma inteligente: si sus tatuajes inhibidores desvían el tiro, invierte la baliza IFF con [F] o vuela la antena explosiva de Arasaka antes de rematar al escuadrón.",
    ),
    "ch_obj_ep03_03": (
        "Extract Memory Sector #03 from the Arasaka cargo crate.",
        "Extrae el Sector de Memoria #03 del contenedor corporativo de Arasaka.",
    ),
    "ch_desc_ep03_03": (
        "With Aiko's cell neutralized, pry S.P.A.R.K.Y. Memory Sector #03 from the Arasaka freight crate on the quay to claim your payout and iconic Smart SMG.",
        "Con la célula de Aiko fuera de combate, extrae el Sector #03 de C.H.I.S.P.A. de la caja de Arasaka en el muelle para cobrar tu paga y tu subfusil inteligente icónico.",
    ),
    "ch_obj_ep03_04": (
        "Talk with SPARKY about the 2023 Arasaka Nuke, Unification War, and the Tyger Claws.",
        "Habla con CHISPA sobre la bomba nuclear de 2023, la Guerra de Unificación y los Garras de Tigre.",
    ),
    "ch_desc_ep03_04": (
        "Memory Sector #03 is linked cleanly across Night City. Ask SPARKY about the 2023 Arasaka Tower bombing, the 2069 Unification War, and Arasaka's shadow pact with the Tyger Claws.",
        "El Sector #03 ya está sincronizado en tus ópticas Kiroshi por toda Night City. Pregunta a CHISPA por el atentado nuclear de 2023, la Guerra de Unificación de 2069 y el pacto oculto entre Arasaka y los Garras de Tigre.",
    ),
    "ch_desc_ep03_done": (
        "You cracked the Tyger Claws smart-jamming screen on the South Watson Waterfront, recovered Memory Sector #03, earned 3,400 eddies plus Contagion Lvl 2 and the iconic Shingen Smart SMG Executive Curve, and uncovered fifty years of corporate war history.",
        "Rompiste la pantalla inhibidora de los Garras de Tigre en el muelle sur de Watson, recuperaste el Sector #03, ganaste 3.400 edis junto a Contagio niv. 2 y el subfusil inteligente icónico «Curva Ejecutiva», y destapaste medio siglo de guerras corporativas.",
    ),
    "ch_shard_ep03_title": (
        "SPARKY STREET FILE // VOL. 3: SMART-LINKS, TIME OF THE RED & UNIFICATION WAR",
        "GUÍA CALLEJERA DE CHISPA // VOL. 3: BALAS INTELIGENTES, ERA DEL ROJO Y UNIFICACIÓN",
    ),
    "ch_shard_ep03_text": (
        "MEMO 01 — SMART GUNS VS. DERMAL JAMMERS: Smart firearms pair guided micro-gyro projectiles with a hand Smart-Link to arc around concrete cover. Wait until you meet Tyger Claws carrying military dermal tattoos: those inked transponders actively bend incoming Smart rounds wide unless you strip their jammer pylon, blind/wipe their optics, or bring an iconic targeting bypass.\n\nMEMO 02 — THE 2023 ARASAKA TOWER NUKE & TIME OF THE RED: During the Fourth Corporate War on August 20, 2023, a Militech strike team—including Morgan Blackhand and Johnny Silverhand—detonated a pocket nuclear charge inside Arasaka's Night City Tower. The fallout turned the sky blood-crimson for years ('The Time of the Red'), forged the City Center rubble heap, and left corpses buried under steel that corpses still deny.\n\nMEMO 03 — UNIFICATION WAR (2069–2070) & TYGER CLAWS: When NUSA President Rosalind Myers and Militech launched a blitz to force Free States back under Washington rule, Night City seemed doomed—until Saburo Arasaka sailed a supercarrier into Coronado Bay. Arasaka kept Night City formally independent... while wiring street muscle like the Tyger Claws with corporate weapons and smuggling corridors across Kabuki and Japantown.",
        "NOTA 01 — ARMAS INTELIGENTES E INHIBIDORES DÉRMICOS: Las armas inteligentes lanzan microproyectiles guiados conectados al Enlace Inteligente de tu palma para curvar el tiro tras cualquier esquina. Sin embargo, los tatuajes dérmicos de Arasaka que llevan los Garras de Tigre interfieren en la guiada y desvían las balas en el último metro salvo que inutilices su baliza IFF, reinicies sus ópticas o dispares con calibración icónica reforzada.\n\nNOTA 02 — LA BOMBA DE ARASAKA DE 2023 Y LA ERA DEL ROJO: El 20 de agosto de 2023, en plena Cuarta Guerra Corporativa entre Militech y Arasaka, un equipo de asalto con Morgan Blackhand y Johnny Silverhand voló la Torre Arasaka con un artefacto nuclear táctico. La ceniza radiactiva tiñó el cielo de escarlata durante años —la Era del Rojo—, borró el centro antiguo y enterró bajo escombros mil secretos que ninguna megaempresa admite todavía.\n\nNOTA 03 — GUERRA DE UNIFICACIÓN (2069–2070) Y GARRAS DE TIGRE: Cuando la presidenta Myers del NUSA y Militech invadieron los Estados Libres para reanexarlos a la fuerza, Night City salvó su independencia gracias a la llegada de un superportaaviones de Arasaka a la bahía. Desde entonces Arasaka domina la sombra financiera mientras usa a bandas como los Garras de Tigre —nacidos en Japantown y ligados al contrabando portuario— como brazo ejecutor negable.",
    ),
    # --- HUD, Mappins, Prompts & Dialogue Choices (Ep. 3) ---
    "ch_mappin_ep03_waterfront": ("SPARKY Ep. 3: South Waterfront Quay", "CHISPA Ep. 3: Muelle Sur de Arasaka"),
    "ch_mappin_ep03_rig": ("SPARKY Ep. 3: Arasaka Cargo Crate", "CHISPA Ep. 3: Alijo Corporativo"),
    "ch_banner_ep03_start": (
        "[SPARKY] Arasaka waterfront echo locked — Check your holophone",
        "[CHISPA] Eco corporativo en el muelle sur — Revisa tu holoteléfono",
    ),
    "ch_banner_ep03_gear": (
        "[SPARKY] Smart pistol Chao & Kiroshi Smart-Bridge online — Route active",
        "[CHISPA] ¡Pistola inteligente Chao y Puente Smart activos! Ruta trazada",
    ),
    "ch_banner_ep03_jammer": (
        "[SPARKY] Tyger Claws IFF Jammer fried! Smart locks 100% lethal",
        "[CHISPA] ¡Inhibidor Garra de Tigre frito! Balas inteligentes al 100 %",
    ),
    "ch_banner_ep03_claimed": (
        "[SPARKY] Sector #03 synced (+3,400 E$, Contagion & Executive Curve)",
        "[CHISPA] Sector #03 conectado (+3.400 €$, Contagio y «Curva Ejecutiva»)",
    ),
    "ch_banner_ep03_done": (
        "[SPARKY] Episode 3 complete — Ready for post-Heist sectors",
        "[CHISPA] Episodio 3 completado — Campaña en Watson finalizada",
    ),
    "ch_hub_ep03_pylon_title": ("ARASAKA // IFF SMART-JAMMER PYLON", "BALIZA INHIBIDORA IFF ARASAKA"),
    "ch_act_invert_pylon": (
        "Invert IFF jammer & spike capacitor [Kiroshi Smart-Bridge]",
        "Invertir baliza IFF y sobrecargar condensador [Kiroshi]",
    ),
    "ch_hub_ep03_rig_title": ("ARASAKA // BLACK-OPS CARGO CRATE", "CONTENEDOR NEGRO DE ARASAKA"),
    "ch_act_claim_sec03": (
        "Extract Memory Sector #03 [S.P.A.R.K.Y.]",
        "Extraer Sector de Memoria #03 [C.H.I.S.P.A.]",
    ),
    "ch_hub_ep03_talk_title": (
        "S.P.A.R.K.Y. // SECTOR #03 (Kiroshi Link)",
        "C.H.I.S.P.A. // SECTOR #03 (Enlace Kiroshi)",
    ),
    "ch_choice_ep03_nuke": (
        "Did Arasaka and Militech really drop a nuke right inside Night City back in 2023?",
        "¿De verdad volaron la Torre Arasaka con una bomba nuclear en medio de Night City en 2023?",
    ),
    "ch_choice_ep03_unification": (
        "How did Night City end up independent from the NUSA after the Unification War?",
        "¿Cómo acabó Night City fuera del NUSA tras la Guerra de Unificación?",
    ),
    "ch_choice_ep03_tygers": (
        "Where did the Tyger Claws start, and why is Arasaka handing them tactical hardware?",
        "¿De dónde salieron los Garras de Tigre y por qué reciben cromo táctico de Arasaka?",
    ),
    "ch_choice_ep03_accept": (
        "Copy that, SPARKY. Let me know once the bridges out of Watson reopen for Sector #04.",
        "Entendido, Chispa. Avísame cuando abran los puentes hacia Heywood para el Sector #04.",
    ),
    # -----------------------------------------------------------------------
    # Episodio 4 — Honor, Chatarra y Patriotas de Cartón (Frontera Arroyo / Heywood)
    # -----------------------------------------------------------------------
    "ch_item_sec04_name": (
        "S.P.A.R.K.Y. Memory Sector #04 (Street Ballistics & 2070 Archive)",
        "Sector de Memoria C.H.I.S.P.A. #04 (Balística y Archivo 2070)",
    ),
    "ch_item_sec04_desc": (
        "Heavy armored tactical memory core rescued from a NUSA surplus smuggling deal on the Heywood–Arroyo border. Restores 2040s–2077 chrome economy logs, Valentinos street history, and 6th Street defector files into S.P.A.R.K.Y. v0.98b.\n\nCOPROCESSOR EXPANSION (PASSIVE): Permanently grants +3 Max Cyberdeck RAM via S.P.A.R.K.Y.'s neural bridge.",
        "Núcleo de memoria táctico rescatado de un trapicheo entre desertores de la Calle 6 y traficantes de Heywood. Restaura los archivos sobre Valentinos, Calle 6 y la economía del cromo en C.H.I.S.P.A. v0.98b.\n\nEXPANSIÓN DE COPROCESADOR (PASIVA): Otorga +3 de RAM máxima permanente al ciberterminal mediante el puente neuronal de C.H.I.S.P.A.",
    ),
    "ch_weapon_masa_name": ("Street Geometry", "Geometría Callejera"),
    "ch_weapon_masa_desc": (
        "Custom Nowaki/Masamune burst assault rifle zeroed by S.P.A.R.K.Y. for corner-banked ricochet fire. Every third-surface bounce turns concrete alleys into lethal crossfire corridors.",
        "Fusil de asalto por ráfagas HJSH-18 Masamune recalibrado por C.H.I.S.P.A. para combate de rebote urbano. Convierte cualquier muro, contenedor o acera de Night City en una esquina letal.",
    ),
    "ch_weapon_masa_ability": (
        "Ballistic Trajectory Suite: +22 Thermal Damage, +15% Crit Chance, +2 Ricochet Bounces, +50% Ricochet Chance, +35% Ricochet Damage, +20% Ricochet Crit Chance, and 20% faster reload.",
        "Óptica de Trayectoria Balística: +22 Daño Térmico, +15% Probabilidad Crítica, +2 Rebotes extra, +50% Probabilidad de Rebote, +35% Daño de Rebote, +20% Probabilidad Crítica al rebote y recarga un 20% más rápida.",
    ),
    "ch_npc_buck_name": ('Sgt. Buck "Stripes" Miller', 'Sargento Buck «Barras» Miller'),
    "ch_scan_buck_desc": (
        "NUSA 4th Corporate War / Unification War veteran turned 6th Street arms broker. High-end subcutaneous plating with an explosive NUSA ammo pallet linked nearby—and lousy ballistic cover awareness against bank shots.",
        "Veterano de la Guerra de Unificación reciclado en traficante de Calle 6. Lleva blindaje dérmico militar conectado a un depósito térmico cercano: un disparo de rebote o una sobrecarga al relé lo dejarán sin cobertura.",
    ),
    "ch_npc_tammy_name": ('Cpl. Tammy "Dogtag" Brooks', 'Cabo Tammy «Chapa» Brooks'),
    "ch_scan_tammy_desc": (
        "6th Street perimeter sharpshooter hoarding stolen Militech copperheads and smart-det crates. Vulnerable around tight concrete angles if V bounces Power rounds off floor plates or walls.",
        "Tiradora veterana de Calle 6 que vigila el intercambio en Arroyo. Vulnerable si usas el visor de trayectoria para hacer rebotar balas de potencia tras su cobertura.",
    ),
    "ch_npc_mateo_name": ('Mateo "Cuervo" Salgado', 'Mateo «Cuervo» Salgado'),
    "ch_scan_mateo_desc": (
        "Heywood Valentinos liaison swapping pre-war chrome and ceremonial revolvers for NUSA heavy hardware. Fast draw with Overture, zero thermal shielding if the ammo reserve detonates.",
        "Enlace de los Valentinos en la frontera de Heywood intercambiando cromo antiguo y revólveres por chatarra del NUSA. Letal a media distancia con su Overture, pero sin blindaje contra explosivos.",
    ),
    "ch_conv_ep04_title": ("ARROYO BORDER // SECTOR 04 PING", "FRONTERA ARROYO // ECO DEL SECTOR 04"),
    "ch_sms_ep04_hook": (
        "Recruit! The Watson bridge blockade finally dropped and my sensors caught Sector #04 pinging in a smugglers' yard between Heywood and Arroyo—right inside a dirty swap between 6th Street and Valentinos. Reply and I'll calibrate live Power Ricochet paths on your Kiroshi and drop a Copperhead.",
        "¡Recluta! Se acabó la cuarentena de Watson: acabo de cazar el Sector #04 entre Heywood y Santo Domingo, en mitad de un trapicheo entre los de Calle 6 y los Valentinos en Arroyo. Contesta para proyectar líneas de rebote balístico en tus Kiroshi y recibir un Copperhead.",
    ),
    "ch_sms_choice_ep04_gangs": (
        "Valentinos and 6th Street trading together? I thought they hated each other.",
        "¿Valentinos y Calle 6 haciendo negocios juntos? Creía que no se podían ni ver.",
    ),
    "ch_sms_choice_ep04_coords": (
        "Fire up the ballistic ricochet visor and send me the Arroyo pin.",
        "Activa el visor de rebote balístico y mándame las coordenadas de Arroyo.",
    ),
    "ch_sms_v_ep04_gangs": (
        "Valentinos and 6th Street trading together? I thought they hated each other.",
        "¿Valentinos y Calle 6 haciendo negocios juntos? Creía que no se podían ni ver.",
    ),
    "ch_sms_reply_ep04_gangs": (
        "Street loyalty ends the second pre-war mil-grade hardware changes hands! Gear sent: Militech Copperhead Power rifle, two Frag grenades, boosters, and full Kiroshi Ricochet preview calibrated.",
        "El honor de barrio dura exactamente hasta que aparece un alijo militar con descuento. Equipo enviado: fusil de potencia Copperhead, dos granadas de fragmentación, curativos y visor de rebote Kiroshi activo.",
    ),
    "ch_sms_v_ep04_coords": (
        "Fire up the ballistic ricochet visor and send me the Arroyo pin.",
        "Activa el visor de rebote balístico y mándame las coordenadas de Arroyo.",
    ),
    "ch_sms_reply_ep04_coords": (
        "Ballistic trajectory bridge locked and yellow GPS active to the Arroyo smuggling yard. Check those ground-bounce angles before Buck opens up, or spike their ballistic relay!",
        "Puente balístico calibrado y ruta amarilla activa hasta el patio de Arroyo. Mira dónde rebotan los trazos en el suelo antes de disparar o sobrecarga su relé balístico.",
    ),
    "ch_sms_ep04_summary": (
        "Sector #04 is synced and Street Geometry is yours! Stay sharp—the last missing fragment just lit up deep inside Pacifica's Combat Zone near the Blackwall border.",
        "¡Sector #04 en línea y «Geometría Callejera» en tu poder! Prepárate: el último fragmento de memoria acaba de emitir un eco brutal desde la Zona de Combate de Pacifica.",
    ),
    "ch_quest_ep04_title": (
        "SPARKY Protocol: Honor, Scrap & Cardboard Patriots",
        "Protocolo CHISPA: Honor, Chatarra y Patriotas de Cartón",
    ),
    "ch_obj_ep04_01": (
        "Answer SPARKY's Arroyo border alert on your holophone.",
        "Responde al aviso de frontera en Arroyo de CHISPA en tu holoteléfono.",
    ),
    "ch_desc_ep04_01": (
        "With Watson unlocked, SPARKY traced Memory Sector #04 to an illegal arms deal between 6th Street veterans and Valentinos enforcers in Arroyo. Reply to his SMS for a Copperhead Power rifle and Kiroshi ricochet preview.",
        "Con Night City abierta tras El Golpe, CHISPA ha localizado el Sector #04 en un intercambio entre veteranos de Calle 6 y Valentinos en Arroyo. Contesta a su SMS para recibir un Copperhead y el visor de rebote.",
    ),
    "ch_obj_ep04_02": (
        "Clear the smuggling yard in Arroyo: bank ricochet shots off cover, spike the ballistic relay, or blow their NUSA ammo tank.",
        "Despeja el patio de Arroyo: castiga con rebotes de potencia, sobrecarga el relé balístico o vuela su depósito NUSA.",
    ),
    "ch_desc_ep04_02": (
        "Approach Buck Miller's smuggling cell in Arroyo. Aim with a Power weapon to preview bullet ricochets into cover, trigger their ballistic relay [F], or detonate the pressurized fuel/ammo drum before taking the Sector.",
        "Acércate al patio del trapicheo en Arroyo. Apunta con un arma de potencia para ver las líneas de rebote contra el suelo o paredes, sobrecarga su relé con [F] o haz estallar el depósito NUSA.",
    ),
    "ch_obj_ep04_03": (
        "Extract Memory Sector #04 from the smuggler crate.",
        "Extrae el Sector de Memoria #04 del alijo de contrabando.",
    ),
    "ch_desc_ep04_03": (
        "With Buck, Tammy, and Mateo neutralized, claim Memory Sector #04 from the green military smuggling rig for 4,200 E$, Cyberware Malfunction Lvl 2, and iconic Masamune Street Geometry.",
        "Con la célula neutralizada, recoge el Sector #04 de la caja verde de contrabando para cobrar 4.200 edis, Fallo de Ciberware niv. 2 y el fusil icónico «Geometría Callejera».",
    ),
    "ch_obj_ep04_04": (
        "Talk with SPARKY about Valentinos, 6th Street, and Night City's chrome economy.",
        "Habla con CHISPA sobre los Valentinos, Calle 6 y el negocio sucio del cromo.",
    ),
    "ch_desc_ep04_04": (
        "Sector #04 is linked cleanly across Night City. Ask SPARKY about Heywood's Valentinos code, 6th Street's NUSA hypocrisy, and the brutal economics of Night City cyberware.",
        "El Sector #04 ya está sincronizado en tus Kiroshi por toda Night City. Pregunta a CHISPA por los Valentinos de Heywood, los patriotas de Calle 6 y el negocio del cromo.",
    ),
    "ch_desc_ep04_done": (
        "You disrupted the 6th Street–Valentinos arms swap in Arroyo, recovered Memory Sector #04, claimed 4,200 eddies plus Cyberware Malfunction Lvl 2 and iconic rifle Street Geometry, and unlocked Pacifica's Blackwall lead.",
        "Reventaste el intercambio entre Calle 6 y Valentinos en Arroyo, recuperaste el Sector #04, cobraste 4.200 edis junto a Fallo de Ciberware niv. 2 y «Geometría Callejera», y fijaste el rastro hacia Pacifica.",
    ),
    "ch_shard_ep04_title": (
        "SPARKY STREET FILE // VOL. 4: POWER RICOCHETS, HEYWOOD, 6TH STREET & CHROME DEBT",
        "GUÍA CALLEJERA DE CHISPA // VOL. 4: REBOTE BALÍSTICO, HEYWOOD, CALLE 6 Y ECONOMÍA DEL CROMO",
    ),
    "ch_shard_ep04_text": (
        "MEMO 01 — POWER WEAPONS & BALLISTIC RICOCHET: Unlike Tech coils or Smart seekers, Power firearms reward sharp bank angles off concrete walls, pavement, and steel containers. Paired with a Ballistic Coprocessor optic preview, ricochets ignore frontal shields and strike targets crouching behind full cover with bonus damage and critical chance.\n\nMEMO 02 — HEYWOOD & THE VALENTINOS: Heywood raised its kids between cathedrals, Santa Muerte shrines, and flashy gold chrome. The Valentinos boast about honor, family, and neighborhood loyalty—and still charge protection tariffs, cut corporate backroom deals, and bury rivals with gold-plated guns.\n\nMEMO 03 — 6TH STREET & THE CHROME TRAP: Born from Unification War veterans who swore to defend Santo Domingo, 6th Street rotted fast into extortion, black-market NUSA arms trafficking, and brutal infighting. Meanwhile, half of Night City finances military cyberware on repo contracts: miss one monthly payment to an employer or loan shark and a back-alley ripper tears the chrome right back out of your ribs.",
        "NOTA 01 — ARMAS DE POTENCIA Y REBOTE BALÍSTICO: Frente a la penetración tecnológica o las balas inteligentes guiadas, las armas de potencia sacan partido a la física pura: al apuntar con un coprocesador balístico ves la línea exacta de rebote en el suelo o las paredes para alcanzar a enemigos agachados tras cobertura con daño y crítico aumentados.\n\nNOTA 02 — HEYWOOD Y LOS VALENTINOS: Entre altares a la Santa Muerte, coches bajos y cromo dorado, los Valentinos presumen de código familiar mientras cobran mordidas, cierran pactos turbios y entierran a quien estorba.\n\nNOTA 03 — CALLE 6 Y LA DEUDA DEL CROMO: Nacidos como patrulla vecinal de excombatientes de la Guerra de Unificación en Santo Domingo, Calle 6 degeneró en traficantes de chatarra militar, extorsión y purgas internas. Y recuerda la regla de oro de Night City: casi nadie paga su cromo al contado; si te quedas sin edis o te echan del curro corporativo, tu implante pasa a embargo.",
    ),
    "ch_mappin_ep04_border": ("SPARKY Ep. 4: Arroyo Smuggler Yard", "CHISPA Ep. 4: Patio de Contrabando (Arroyo)"),
    "ch_mappin_ep04_rig": ("SPARKY Ep. 4: Border Arms Crate", "CHISPA Ep. 4: Alijo Fronterizo"),
    "ch_banner_ep04_start": (
        "[SPARKY] City bridges open — Sector #04 signal in Arroyo",
        "[CHISPA] Puentes abiertos — Eco del Sector #04 en Arroyo",
    ),
    "ch_banner_ep04_gear": (
        "[SPARKY] Copperhead & Kiroshi Ricochet Bridge active — Route traced",
        "[CHISPA] ¡Copperhead y visor de rebote activos! Ruta a Arroyo fijada",
    ),
    "ch_banner_ep04_cache": (
        "[SPARKY] Ballistic relay & NUSA ammo tank detonated!",
        "[CHISPA] ¡Relé balístico y depósito NUSA reventados!",
    ),
    "ch_banner_ep04_claimed": (
        "[SPARKY] Sector #04 synced (+4,200 E$, Cyberware Malfunction & Street Geometry)",
        "[CHISPA] Sector #04 conectado (+4.200 €$, Fallo Ciberware y «Geometría Callejera»)",
    ),
    "ch_banner_ep04_done": (
        "[SPARKY] Episode 4 complete — Final trace locking onto Pacifica",
        "[CHISPA] Episodio 4 completado — Último rastro detectado en Pacifica",
    ),
    "ch_hub_ep04_relay_title": ("6TH STREET // BALLISTIC TELEMETRY RELAY", "RELÉ BALÍSTICO // CALLE 6"),
    "ch_act_overload_ep04": (
        "Spike thermal relay into NUSA ammo tank [Kiroshi]",
        "Sobrecargar relé hacia el depósito de munición NUSA [Kiroshi]",
    ),
    "ch_hub_ep04_rig_title": ("BORDER SMUGGLER // ARROYO CRATE", "ALIJO FRONTERIZO // ARROYO"),
    "ch_act_claim_sec04": (
        "Extract Memory Sector #04 [S.P.A.R.K.Y.]",
        "Extraer Sector de Memoria #04 [C.H.I.S.P.A.]",
    ),
    "ch_hub_ep04_talk_title": (
        "S.P.A.R.K.Y. // SECTOR #04 (Kiroshi Link)",
        "C.H.I.S.P.A. // SECTOR #04 (Enlace Kiroshi)",
    ),
    "ch_choice_ep04_valentinos": (
        "How did Heywood turn out so caught up in Valentinos faith, gold chrome, and turf blood?",
        "¿Cómo acabó Heywood tan metido entre el culto, el oro y las guerras de los Valentinos?",
    ),
    "ch_choice_ep04_sixth": (
        "What turned 6th Street from neighborhood war vets into NUSA gunrunners?",
        "¿En qué momento pasó Calle 6 de veteranos vecinales a traficantes armados?",
    ),
    "ch_choice_ep04_chrome": (
        "How does regular folks' cyberware actually work here—do people go broke paying off their own arms?",
        "¿Cómo aguanta la gente de a pie tanta operación de cromo sin acabar desguazada por las deudas?",
    ),
    "ch_choice_ep04_accept": (
        "Copy that, SPARKY. Let's hunt down the final Sector #05 in Pacifica.",
        "Recibido, Chispa. Vamos a cazar el último Sector #05 en Pacifica.",
    ),
    # -----------------------------------------------------------------------
    # Episodio 5 — Más Allá del Muro Negro (Coastview, Pacifica — Final Temporada 1)
    # -----------------------------------------------------------------------
    "ch_item_sec05_name": (
        "S.P.A.R.K.Y. Master Core Sector #05 (2022 Blackwall Kernel)",
        "Sector Maestro C.H.I.S.P.A. #05 (Núcleo del Muro Negro 2022)",
    ),
    "ch_item_sec05_desc": (
        "S.P.A.R.K.Y.'s original 2022 Zetatech concierge kernel—carved apart by a Bartmoss decker days before the DataKrash and recovered from a Voodoo Boys / NetWatch proxy vault in Pacifica.\n\nCOPROCESSOR EXPANSION (PASSIVE): Permanently grants +3 Max Cyberdeck RAM via S.P.A.R.K.Y.'s neural bridge.",
        "El núcleo original de 2022 de C.H.I.S.P.A., amputado por un netrunner del círculo de Bartmoss justo antes del DataKrash y recuperado de los Hijos del Vudú en Pacifica.\n\nEXPANSIÓN DE COPROCESADOR (PASIVA): Otorga +3 de RAM máxima permanente al ciberterminal mediante el puente neuronal de C.H.I.S.P.A.",
    ),
    "ch_weapon_ken_name": ("Firewall '22", "Cortafuegos del 22"),
    "ch_weapon_ken_desc": (
        "Arasaka JKE-X2 Kenshin Tech pistol rebuilt with S.P.A.R.K.Y.'s liberated 2022 telemetry kernel. Punches dual electric-thermal beams straight through concrete while overclocking reload speed.",
        "Pistola tecnológica Arasaka Kenshin reconstruida con los registros liberados de 2022 de C.H.I.S.P.A. Atraviesa cobertura sólida con descarga doble eléctrica y térmica.",
    ),
    "ch_weapon_ken_ability": (
        "2022 Barrier Breaker: +26 Electric Damage, +20 Thermal Damage, +18% Crit Chance, 26% faster Tech charge, +25% Armor/Wall-Pierce Damage, and 22% faster reload.",
        "Ruptura del 22: +26 Daño Eléctrico, +20 Daño Térmico, +18% Probabilidad Crítica, carga tecnológica un 26% más rápida, +25% daño al atravesar muros y recarga un 22% más rápida.",
    ),
    "ch_weapon_over_name": ("Sergeant's Last Word", "Última Palabra de Sargento"),
    "ch_weapon_over_desc": (
        "Malorian-inspired Overture heavy revolver infused with S.P.A.R.K.Y.'s peak combat subroutine—forged exclusively if V melts the drill sergeant's tactical instincts into iron.",
        "Revólver pesado Overture forjado a medida con la subrutina balística completa de C.H.I.S.P.A.: precisión quirúrgica a la cabeza, descarga eléctrica y doble rebote letal.",
    ),
    "ch_weapon_over_ability": (
        "Drill Sergeant Protocol: +32 Electric Damage, +20% Crit Chance, +35% Headshot Multiplier, +2 Ricochet Bounces, +40% Ricochet Damage, and 20% faster reload.",
        "Protocolo Sargento Supremo: +32 Daño Eléctrico, +20% Probabilidad Crítica, +35% Multiplicador en Cabeza, +2 Rebotes extra, +40% Daño de Rebote y recarga un 20% más rápida.",
    ),
    "ch_cam_ep05_perim": ("CAM-01 PACIFICA PERIMETER", "CAM-01 PERÍMETRO PACIFICA"),
    "ch_cam_ep05_server": ("CAM-02 BLACKWALL NODE", "CAM-02 NODO MURO NEGRO"),
    "ch_npc_tiluc_name": ('Ti-Luc "Loa" Desrosiers', 'Ti-Luc «Loa» Desrosiers'),
    "ch_scan_tiluc_desc": (
        "Rogue Voodoo Boys netrunner cell boss harvesting pre-DataKrash corporate AIs near a NetWatch proxy pylon. Runs active Blackwall subnet cameras and an unstable cryogenic server bank.",
        "Líder de célula de los Hijos del Vudú cosechando fragmentos de IA previos al DataKrash en Coastview. Opera dos cámaras en cadena y un servidor criogénico explosivo.",
    ),
    "ch_npc_mireille_name": ('Mireille "Shadow" Jean-Baptiste', 'Mireille «Sombra» Jean-Baptiste'),
    "ch_scan_mireille_desc": (
        "Voodoo Boys ranged breach specialist equipped with Sidewinder Smart locks. Takes severe electrical splash if the cryogenic containment server or NetWatch pylon spikes.",
        "Especialista vudú armada con fusil inteligente Sidewinder. Muy vulnerable a la descarga en cadena si revientas el servidor criogénico o el pilón de NetWatch.",
    ),
    "ch_npc_brutus_name": ('Brutus "Sledge" Kowalski', 'Brutus «Maza» Kowalski'),
    "ch_scan_brutus_desc": (
        "Hired Animals chrome heavy acting as disposable perimeter muscle for the Voodoo Boys—just like Placide's usual play. Vulnerable to Short Circuit, Cyberware Malfunction, or flanking ricochets.",
        "Matón cromado de los Animales contratado como carne de cañón desechable por los Hijos del Vudú. Muy vulnerable a Cortocircuito o al sabotaje del pilón de contención.",
    ),
    "ch_conv_ep05_title": ("COASTVIEW, PACIFICA // MASTER KERNEL 05", "COASTVIEW, PACIFICA // NÚCLEO MAESTRO 05"),
    "ch_sms_ep05_hook": (
        "Recruit... stop everything. Sector #05—my original 2022 root memory—just screamed out of Coastview, Pacifica. A Voodoo Boys crew with rented Animals muscle is dissecting it beside a live NetWatch containment beacon. Reply for heavy EMP tools and full Kiroshi combat bridges.",
        "Recluta... detén lo que estés haciendo. Mi Sector #05 —el núcleo maestro original de 2022— acaba de lanzar un grito desde Coastview, en Pacifica. Los Hijos del Vudú y matones de los Animales lo están destripando junto a una baliza de NetWatch. Responde para activar todos los puentes Kiroshi y recibir granadas PEM.",
    ),
    "ch_sms_choice_ep05_voodoo": (
        "Voodoo Boys plus Animals muscle? Wait—I thought they treated outsiders as disposable.",
        "¿Hijos del Vudú usando matones de los Animales? Creía que los trataban como carne descartable.",
    ),
    "ch_sms_choice_ep05_pacifica": (
        "Send the EMP payload, sync all Kiroshi bridges, and drop the Pacifica coordinates.",
        "Manda el equipo PEM, activa todos los puentes Kiroshi y dime dónde está el nodo en Pacifica.",
    ),
    "ch_sms_v_ep05_voodoo": (
        "Voodoo Boys plus Animals muscle? Wait—I thought they treated outsiders as disposable.",
        "¿Hijos del Vudú usando matones de los Animales? Creía que los trataban como carne descartable.",
    ),
    "ch_sms_reply_ep05_voodoo": (
        "They DO treat hired ranyons as disposable—that's why bringing down their containment pylon fries both squads! Gear shipped: EMP grenades, Tier-3 Short Circuit, and all Kiroshi combat links active.",
        "Lo son, exacto: por eso si sobrecargas su baliza de NetWatch o el servidor criogénico, la descarga barre a ambos bandos. Enviado: granadas PEM, Cortocircuito niv. 3 y todos tus puentes Kiroshi al máximo.",
    ),
    "ch_sms_v_ep05_pacifica": (
        "Send the EMP payload, sync all Kiroshi bridges, and drop the Pacifica coordinates.",
        "Manda el equipo PEM, activa todos los puentes Kiroshi y dime dónde está el nodo en Pacifica.",
    ),
    "ch_sms_reply_ep05_pacifica": (
        "Master route pinned to Coastview, Pacifica! Combine everything we drilled across Night City: chained cameras, EMP, Tech wall-piercing, Smart curve shots, or Power ricochets.",
        "¡Ruta final trazada hacia Coastview, Pacifica! Ya sabes todo lo que hace falta en Night City: cámaras en cadena, PEM, penetración tecnológica, balas inteligentes o rebotes.",
    ),
    "ch_sms_ep05_summary": (
        "Season 1 Memory Array 100% restored! Check your Codex for the complete Zetatech 2022 Night City street file—and thanks for pulling this old sergeant out of a dark H10 alley.",
        "¡Memoria de Temporada 1 restaurada al 100 %! Ya tienes los cinco volúmenes del códice en tu diario... y gracias por no dejarme oxidado en aquel callejón trasero de Watson, recluta.",
    ),
    "ch_quest_ep05_title": (
        "SPARKY Protocol: Beyond the Blackwall",
        "Protocolo CHISPA: Más Allá del Muro Negro",
    ),
    "ch_obj_ep05_01": (
        "Reply to SPARKY's final Pacifica alert on your holophone.",
        "Responde al aviso final de CHISPA en Pacifica en tu holoteléfono.",
    ),
    "ch_desc_ep05_01": (
        "SPARKY's master 2022 memory core turned up in Coastview, Pacifica, flanked by Voodoo Boys netrunners and Animals mercenaries near a NetWatch beacon. Answer his text to deploy EMP tools and full Kiroshi bridges.",
        "El Sector Maestro #05 de 2022 ha aparecido en Coastview (Pacifica) vigilado por los Hijos del Vudú y mercenarios de los Animales junto a un pilón de NetWatch. Responde al SMS para armarte.",
    ),
    "ch_obj_ep05_02": (
        "Neutralize the Voodoo Boys & Animals cell in Pacifica using any mastery style—netrunning, Tech pierce, ricochets, or containment purge.",
        "Neutraliza a los Hijos del Vudú y Animales en Pacifica combinando netrunning, balística o la purga de contención.",
    ),
    "ch_desc_ep05_02": (
        "Engage Ti-Luc's cell in Coastview, Pacifica. Hijack their chained CAM-01/CAM-02 subnet, purge the NetWatch containment pylon [F], blow the cryogenic server, or dismantle them with your full arsenal.",
        "Enfréntate a Ti-Luc en Coastview, Pacifica. Secuestra la cadena de cámaras CAM-01/CAM-02, purga la baliza de contención de NetWatch con [F], vuela su servidor o acaba con ellos combinando todo tu arsenal.",
    ),
    "ch_obj_ep05_03": (
        "Recover Master Sector #05 from the Pacifica vault rig.",
        "Recupera el Sector Maestro #05 del nodo de Pacifica.",
    ),
    "ch_desc_ep05_03": (
        "With Coastview clear, link Master Sector #05 into S.P.A.R.K.Y. to claim 5,000 E$, System Collapse Lvl 3, iconic Tech pistol Firewall '22, and unlock SPARKY's full 2022 truth.",
        "Con Coastview despejado, extrae el Sector Maestro #05 del nodo azul para obtener 5.000 edis, Colapso del Sistema niv. 3, la pistola icónica «Cortafuegos del 22» y la verdad de 2022.",
    ),
    "ch_obj_ep05_04": (
        "Seal S.P.A.R.K.Y.'s Season 1 fate across Pacifica's skyline.",
        "Decide el destino final de C.H.I.S.P.A. en la charla de cierre.",
    ),
    "ch_desc_ep05_04": (
        "All five memory sectors are synced across Night City. Hear S.P.A.R.K.Y.'s true 2022 origin and choose his destiny: permanent Kiroshi partner, open N54 data leak, or custom iconic gunsmith fusion.",
        "Con los cinco sectores sincronizados, escucha la verdad sobre el origen de C.H.I.S.P.A. en 2022 y elige su destino final: socio permanente en tus Kiroshi, filtración abierta a N54 o fusión armera icónica.",
    ),
    "ch_desc_ep05_done": (
        "You broke the Voodoo Boys & Animals blockade in Coastview, Pacifica, restored all five S.P.A.R.K.Y. memory sectors from 1998 to 2077, claimed iconic Tech pistol Firewall '22, and forged S.P.A.R.K.Y.'s final pact.",
        "Superaste la emboscada de los Hijos del Vudú y Animales en Coastview (Pacifica), restauraste los cinco sectores de memoria de C.H.I.S.P.A., obtuviste la pistola tecnológica icónica «Cortafuegos del 22» y sellaste el destino del viejo sargento holográfico.",
    ),
    "ch_shard_ep05_title": (
        "SPARKY STREET FILE // VOL. 5: PACIFICA, VOODOO BOYS & THE BLACKWALL FRONTIER",
        "GUÍA CALLEJERA DE CHISPA // VOL. 5: PACIFICA, HIJOS DEL VUDÚ Y LA FRONTERA DEL MURO NEGRO",
    ),
    "ch_shard_ep05_text": (
        "MEMO 01 — PACIFICA'S CORPSE-RESORT RUINS: Built to be Night City's glittering luxury playground before corporate investors pulled out during the Unification War scare, Pacifica collapsed into skeleton towers, squatter markets, and NCPD abandonment. Coastview became an independent Combat Zone overnight.\n\nMEMO 02 — VOODOO BOYS, NETWATCH & THE BLACKWALL: Led by Haitian survivors after climate catastrophe drowned their homeland, the Voodoo Boys guard Pacifica behind lethal netrunning walls while probing past NetWatch's Blackwall—the sentient containment AI separating Night City's local nets from the rogue killers still swarming Rache Bartmoss's ruined 2022 Old Net. To them, outside edgerunners (ranyons) are merely paid fuses.\n\nMEMO 03 — PROJECT S.P.A.R.K.Y. (ZETATECH 2022 ARCHIVE): Manufactured in 2022 as 'Executive Concierge v0.98b' and secretly rewired by a Bartmoss apprentice with the personality engram of an actual Night City NCO instructor, SPARKY survived inside locked titanium hardware until V plugged in behind Megabuilding H10.",
        "NOTA 01 — PACIFICA, EL PARAÍSO ABANDONADO: Proyectada como complejo de lujo corporativo y abandonada a medio construir cuando los inversores huyeron antes de la Guerra de Unificación, Pacifica se convirtió en Zona de Combate independiente sin presencia oficial del NCPD.\n\nNOTA 02 — HIJOS DEL VUDÚ, NETWATCH Y EL MURO NEGRO: Nacidos de la diáspora haitiana tras desastres climáticos, los Hijos del Vudú dominan Pacifica con ICE letal mientras buscan brechas tras el Muro Negro —el cortafuegos inteligente con el que NetWatch contiene a las IAs asesinas de la vieja Red infectada por Bartmoss en 2022—. Para ellos, cualquier mercenario externo es solo un fusible desechable.\n\nNOTA 03 — EXPEDIENTE C.H.I.S.P.A. v0.98b (ZETATECH 2022): Fabricado como asistente ejecutivo corporativo y reescrito días antes del DataKrash por un aprendiz de Bartmoss usando los modales de un sargento chusquero real de 2022, C.H.I.S.P.A. sobrevivió cincuenta y cinco años aislado hasta cruzarse con V tras H10.",
    ),
    "ch_mappin_ep05_pacifica": ("SPARKY Ep. 5: Coastview Blackwall Node", "CHISPA Ep. 5: Nodo Coastview (Pacifica)"),
    "ch_mappin_ep05_rig": ("SPARKY Ep. 5: Master Core Vault", "CHISPA Ep. 5: Bóveda Sector Maestro #05"),
    "ch_banner_ep05_start": (
        "[SPARKY] Master Kernel #05 screaming out of Coastview, Pacifica",
        "[CHISPA] ¡Núcleo Maestro #05 localizado en Coastview, Pacifica!",
    ),
    "ch_banner_ep05_gear": (
        "[SPARKY] EMP kit & all Kiroshi combat bridges synced — Route live",
        "[CHISPA] ¡Kit PEM y puentes Kiroshi completos activos! Ruta a Pacifica abierta",
    ),
    "ch_banner_ep05_cryo": (
        "[SPARKY] Containment beacon & cryo-server purged across Coastview!",
        "[CHISPA] ¡Baliza NetWatch y servidor criogénico purgados en Pacifica!",
    ),
    "ch_banner_ep05_claimed": (
        "[SPARKY] Master Sector #05 synced (+5,000 E$, System Collapse & Firewall '22)",
        "[CHISPA] Sector Maestro #05 conectado (+5.000 €$, Colapso Sistema y «Cortafuegos del 22»)",
    ),
    "ch_banner_ep05_end_partner": (
        "[SPARKY v1.0] Autonomous Kiroshi Partner active (+1,500 E$ & Synapse Burnout)",
        "[CHISPA v1.0] Socio autónomo fijado en tus Kiroshi (+1.500 €$ y Sinapsis Calcinada)",
    ),
    "ch_banner_ep05_end_leak": (
        "[SPARKY // N54] 2022 Corporate dirty archive leaked (+4,500 E$ & Cyberware Malfunction)",
        "[CHISPA // N54] ¡Archivo 2022 filtrado a N54! (+4.500 €$ y Fallo Ciberware)",
    ),
    "ch_banner_ep05_end_gunsmith": (
        "[SPARKY // ARMORY] Season 1 complete — Iconic revolver \"Sergeant's Last Word\" forged!",
        "[CHISPA // ARMERÍA] ¡Temporada 1 completada! Forjada «Última Palabra de Sargento»",
    ),
    "ch_hub_ep05_pylon_title": ("NETWATCH // PACIFICA CONTAINMENT PYLON", "BALIZA DE CONTENCIÓN // NETWATCH"),
    "ch_act_purge_ep05": (
        "Overload Blackwall containment pulse into Voodoo server [Kiroshi]",
        "Purgar pulso de contención contra el servidor vudú [Kiroshi]",
    ),
    "ch_hub_ep05_rig_title": ("COASTVIEW // MASTER KERNEL VAULT #05", "NODO MAESTRO #05 // COASTVIEW"),
    "ch_act_claim_sec05": (
        "Recover Master Memory Sector #05 [S.P.A.R.K.Y.]",
        "Recuperar Sector Maestro #05 [C.H.I.S.P.A.]",
    ),
    "ch_hub_ep05_talk_title": (
        "S.P.A.R.K.Y. // MASTER KERNEL 2022 (Kiroshi Link)",
        "C.H.I.S.P.A. // NÚCLEO MAESTRO 2022 (Enlace Kiroshi)",
    ),
    "ch_choice_ep05_pacifica": (
        "How did Pacifica go from shiny corpo resort dream to this abandoned warzone?",
        "¿Cómo pasó Pacifica de proyecto de resort corporativo a esta ruina sin ley?",
    ),
    "ch_choice_ep05_voodoo": (
        "Why do the Voodoo Boys keep poking past NetWatch's Blackwall despite the danger?",
        "¿Por qué se juegan el cuello los Hijos del Vudú hurgando tras el Muro Negro?",
    ),
    "ch_choice_ep05_origin": (
        "All five memory sectors are back—who really built you in 2022, SPARKY?",
        "Con los cinco sectores enteros... ¿quién te programó realmente en 2022, Chispa?",
    ),
    "ch_choice_ep05_end_partner": (
        "[Partner v1.0] Keep full autonomy inside my Kiroshi—you're staying on active duty.",
        "[Socio v1.0] Quédate autónomo en mis Kiroshi; seguimos patrullando juntos Night City.",
    ),
    "ch_choice_ep05_end_leak": (
        "[N54 Public Leak] Blast the unredacted 2022 corpo dirt to N54 News and cash in big.",
        "[Filtración N54] Filtra todo el archivo oculto de 2022 a la prensa libre y reparte el cheque.",
    ),
    "ch_choice_ep05_end_gunsmith": (
        "[Gunsmith Protocol] Print your combat instincts into one final iconic Overture prototype.",
        "[Protocolo Armero] Vuelca tu subrutina balística en un último prototipo icónico Overture.",
    ),
    "ch_holo_telemetry_title": ("S.P.A.R.K.Y. v0.98b", "C.H.I.S.P.A. v0.98b"),
    "ch_holo_telemetry_sub": ("DRILL SERGEANT // UNFILTERED", "MODO SARGENTO // SIN FILTRO"),
    "ch_banner_dbg_unlock": (
        "[SPARKY] Watson bridges & Fast Travel unlocked for testing",
        "[CHISPA] Puentes de Watson y Viaje Rápido desbloqueados para pruebas",
    ),
    "ch_banner_dbg_ep01": (
        "[SPARKY] Episode 1 activated — Check your holophone in Kabuki",
        "[CHISPA] Episodio 1 activado — Revisa tu holoteléfono en Kabuki",
    ),
    "ch_banner_dbg_ep02": (
        "[SPARKY] Episode 2 activated — Check your holophone in Northside",
        "[CHISPA] Episodio 2 activado — Revisa tu holoteléfono en Northside",
    ),
    "ch_banner_dbg_ep03": (
        "[SPARKY] Episode 3 activated — Check your holophone at South Waterfront",
        "[CHISPA] Episodio 3 activado — Revisa tu holoteléfono en el muelle sur",
    ),
    "ch_banner_dbg_ep04": (
        "[SPARKY] Episode 4 activated — Check your holophone post-lockdown",
        "[CHISPA] Episodio 4 activado — Revisa tu holoteléfono tras el bloqueo",
    ),
    "ch_banner_dbg_ep05": (
        "[SPARKY] Episode 5 activated — Check your holophone bound for Pacifica",
        "[CHISPA] Episodio 5 activado — Revisa tu holoteléfono rumbo a Pacifica",
    ),
}


class HandleCounter:
    def __init__(self) -> None:
        self.val = 0

    def next(self) -> str:
        out = str(self.val)
        self.val += 1
        return out


def _loc_val(key: str) -> dict[str, str]:
    return {"unk1": "0", "value": key}


def _tdb_uint0() -> dict[str, str]:
    return {"$type": "TweakDBID", "$storage": "uint64", "$value": "0"}


def _tdb_str(val: str) -> dict[str, str]:
    return {"$type": "TweakDBID", "$storage": "string", "$value": val}


def _noderef0() -> dict[str, str]:
    return {"$type": "NodeRef", "$storage": "uint64", "$value": "0"}


def _cname_str(val: str) -> dict[str, str]:
    return {"$type": "CName", "$storage": "string", "$value": val}


def build_journal_json() -> dict[str, Any]:
    hc = HandleCounter()

    def make_node(type_name: str, **kwargs: Any) -> dict[str, Any]:
        h = hc.next()
        obj: dict[str, Any] = {"$type": type_name}
        obj.update(kwargs)
        return {"HandleId": h, "Data": obj}

    def make_quest_mappin_node(pin_id: str, caption_key: str, x: float, y: float, z: float) -> dict[str, Any]:
        ANCHOR_NODEREF = "#q101_mp_to_elev_helper1"
        ANCHOR_X = -1402.38293
        ANCHOR_Y = 1289.48730
        ANCHOR_Z = 119.97745
        return make_node(
            "gameJournalQuestMapPin",
            enableGPS=1,
            entries=[],
            id=pin_id,
            journalEntryOverrideDataList=[],
            mappinData={
                "$type": "gamemappinsMappinData",
                "active": 1,
                "debugCaption": "",
                "localizedCaption": _loc_val(caption_key),
                "mappinType": _tdb_str("Mappins.QuestStaticMappinDefinition"),
                "scriptData": None,
                "variant": "ExclamationMarkVariant",
                "visibleThroughWalls": 1,
            },
            offset={
                "$type": "Vector3",
                "X": round(x - ANCHOR_X, 3),
                "Y": round(y - ANCHOR_Y, 3),
                "Z": round(z - ANCHOR_Z, 3),
            },
            reference={
                "$type": "gameEntityReference",
                "dynamicEntityUniqueName": _cname_str("None"),
                "names": [],
                "reference": {
                    "$type": "NodeRef",
                    "$storage": "string",
                    "$value": ANCHOR_NODEREF,
                },
                "sceneActorContextName": _cname_str("None"),
                "slotName": _cname_str("None"),
                "type": "EntityRef",
            },
            slotName=_cname_str("None"),
            uiAnimation=_tdb_uint0(),
        )

    def build_quest_entry(
        quest_id: str,
        title_key: str,
        district_id: str,
        phase_id: str,
        objectives_spec: list[tuple[str, str, str, str, str, Any]],
        done_desc_id: str,
        done_desc_key: str,
    ) -> dict[str, Any]:
        q_h = hc.next()
        ph_h = hc.next()
        phase_entries: list[dict[str, Any]] = []
        for oid, okey, did, dkey, obj_district, mappin_spec in objectives_spec:
            obj_h = hc.next()
            obj_children: list[dict[str, Any]] = [
                make_node(
                    "gameJournalQuestDescription",
                    description=_loc_val(dkey),
                    id=did,
                    journalEntryOverrideDataList=[],
                )
            ]
            if mappin_spec is not None:
                obj_children.append(make_quest_mappin_node(*mappin_spec))
            phase_entries.append(
                {
                    "HandleId": obj_h,
                    "Data": {
                        "$type": "gameJournalQuestObjective",
                        "counter": 0,
                        "description": _loc_val(okey),
                        "districtID": obj_district,
                        "entries": obj_children,
                        "id": oid,
                        "itemID": _tdb_uint0(),
                        "journalEntryOverrideDataList": [],
                        "locationPrefabRef": _noderef0(),
                        "optional": 0,
                    },
                }
            )
        phase_entries.append(
            make_node(
                "gameJournalQuestDescription",
                description=_loc_val(done_desc_key),
                id=done_desc_id,
                journalEntryOverrideDataList=[],
            )
        )
        return {
            "HandleId": q_h,
            "Data": {
                "$type": "gameJournalQuest",
                "districtID": district_id,
                "id": quest_id,
                "journalEntryOverrideDataList": [],
                "recommendedLevelID": _tdb_str("DeviceContentAssignment.q001"),
                "title": _loc_val(title_key),
                "type": "SideQuest",
                "entries": [
                    {
                        "HandleId": ph_h,
                        "Data": {
                            "$type": "gameJournalQuestPhase",
                            "id": phase_id,
                            "journalEntryOverrideDataList": [],
                            "locationPrefabRef": _noderef0(),
                            "entries": phase_entries,
                        },
                    }
                ],
            },
        }

    root_handle = hc.next()
    quests_handle = hc.next()
    side_quest_handle = hc.next()

    ep00_objectives = [
        ("01_answer_sms", "ch_obj_ep00_01", "desc_ep00_01", "ch_desc_ep00_01", "Districts.LittleChina", None),
        ("02_clear_alley", "ch_obj_ep00_02", "desc_ep00_02", "ch_desc_ep00_02", "Districts.LittleChina", ("mp_ep00_alley", "ch_mappin_ep00_alley", -1338.69, 1264.53, 18.20)),
        ("03_claim_chispa", "ch_obj_ep00_03", "desc_ep00_03", "ch_desc_ep00_03", "Districts.LittleChina", ("mp_ep00_console", "ch_mappin_ep00_console", -1338.69, 1264.53, 18.20)),
        ("04_talk_chispa", "ch_obj_ep00_04", "desc_ep00_04", "ch_desc_ep00_04", "Districts.LittleChina", None),
    ]
    ep01_objectives = [
        ("01_ep01_sms", "ch_obj_ep01_01", "desc_ep01_01", "ch_desc_ep01_01", "Districts.Kabuki", None),
        ("02_ep01_infiltrate", "ch_obj_ep01_02", "desc_ep01_02", "ch_desc_ep01_02", "Districts.Kabuki", ("mp_ep01_kabuki", "ch_mappin_ep01_kabuki", -990.60, 1615.80, 3.85)),
        ("03_ep01_extract", "ch_obj_ep01_03", "desc_ep01_03", "ch_desc_ep01_03", "Districts.Kabuki", ("mp_ep01_terminal", "ch_mappin_ep01_terminal", -985.90, 1630.90, 3.85)),
        ("04_ep01_talk", "ch_obj_ep01_04", "desc_ep01_04", "ch_desc_ep01_04", "Districts.Kabuki", None),
    ]
    ep02_objectives = [
        ("01_ep02_sms", "ch_obj_ep02_01", "desc_ep02_01", "ch_desc_ep02_01", "Districts.Northside", None),
        ("02_ep02_clear", "ch_obj_ep02_02", "desc_ep02_02", "ch_desc_ep02_02", "Districts.Northside", ("mp_ep02_northside", "ch_mappin_ep02_northside", -1555.80, 2647.80, 8.40)),
        ("03_ep02_extract", "ch_obj_ep02_03", "desc_ep02_03", "ch_desc_ep02_03", "Districts.Northside", ("mp_ep02_rig", "ch_mappin_ep02_rig", -1556.90, 2659.20, 8.55)),
        ("04_ep02_talk", "ch_obj_ep02_04", "desc_ep02_04", "ch_desc_ep02_04", "Districts.Northside", None),
    ]
    ep03_objectives = [
        ("01_ep03_sms", "ch_obj_ep03_01", "desc_ep03_01", "ch_desc_ep03_01", "Districts.LittleChina", None),
        ("02_ep03_clear", "ch_obj_ep03_02", "desc_ep03_02", "ch_desc_ep03_02", "Districts.LittleChina", ("mp_ep03_waterfront", "ch_mappin_ep03_waterfront", -2021.20, 1556.80, 10.35)),
        ("03_ep03_extract", "ch_obj_ep03_03", "desc_ep03_03", "ch_desc_ep03_03", "Districts.LittleChina", ("mp_ep03_rig", "ch_mappin_ep03_rig", -2022.40, 1571.60, 10.45)),
        ("04_ep03_talk", "ch_obj_ep03_04", "desc_ep03_04", "ch_desc_ep03_04", "Districts.LittleChina", None),
    ]
    ep04_objectives = [
        ("01_ep04_sms", "ch_obj_ep04_01", "desc_ep04_01", "ch_desc_ep04_01", "Districts.Arroyo", None),
        ("02_ep04_clear", "ch_obj_ep04_02", "desc_ep04_02", "ch_desc_ep04_02", "Districts.Arroyo", ("mp_ep04_border", "ch_mappin_ep04_border", -913.50, -1025.80, 13.10)),
        ("03_ep04_extract", "ch_obj_ep04_03", "desc_ep04_03", "ch_desc_ep04_03", "Districts.Arroyo", ("mp_ep04_rig", "ch_mappin_ep04_rig", -913.50, -1022.40, 13.10)),
        ("04_ep04_talk", "ch_obj_ep04_04", "desc_ep04_04", "ch_desc_ep04_04", "Districts.Arroyo", None),
    ]
    ep05_objectives = [
        ("01_ep05_sms", "ch_obj_ep05_01", "desc_ep05_01", "ch_desc_ep05_01", "Districts.Coastview", None),
        ("02_ep05_clear", "ch_obj_ep05_02", "desc_ep05_02", "ch_desc_ep05_02", "Districts.Coastview", ("mp_ep05_pacifica", "ch_mappin_ep05_pacifica", -2518.50, -2341.00, 10.25)),
        ("03_ep05_extract", "ch_obj_ep05_03", "desc_ep05_03", "ch_desc_ep05_03", "Districts.Coastview", ("mp_ep05_rig", "ch_mappin_ep05_rig", -2518.50, -2336.80, 10.25)),
        ("04_ep05_talk", "ch_obj_ep05_04", "desc_ep05_04", "ch_desc_ep05_04", "Districts.Coastview", None),
    ]

    quest_ep00_node = build_quest_entry(
        "chispa_nc_quest",
        "ch_quest_title",
        "Districts.LittleChina",
        "phase_ep00",
        ep00_objectives,
        "desc_ep00_done",
        "ch_desc_ep00_done",
    )
    quest_ep01_node = build_quest_entry(
        "chispa_ep01_quest",
        "ch_quest_ep01_title",
        "Districts.Kabuki",
        "phase_ep01",
        ep01_objectives,
        "desc_ep01_done",
        "ch_desc_ep01_done",
    )
    quest_ep02_node = build_quest_entry(
        "chispa_ep02_quest",
        "ch_quest_ep02_title",
        "Districts.Northside",
        "phase_ep02",
        ep02_objectives,
        "desc_ep02_done",
        "ch_desc_ep02_done",
    )
    quest_ep03_node = build_quest_entry(
        "chispa_ep03_quest",
        "ch_quest_ep03_title",
        "Districts.LittleChina",
        "phase_ep03",
        ep03_objectives,
        "desc_ep03_done",
        "ch_desc_ep03_done",
    )
    quest_ep04_node = build_quest_entry(
        "chispa_ep04_quest",
        "ch_quest_ep04_title",
        "Districts.Arroyo",
        "phase_ep04",
        ep04_objectives,
        "desc_ep04_done",
        "ch_desc_ep04_done",
    )
    quest_ep05_node = build_quest_entry(
        "chispa_ep05_quest",
        "ch_quest_ep05_title",
        "Districts.Coastview",
        "phase_ep05",
        ep05_objectives,
        "desc_ep05_done",
        "ch_desc_ep05_done",
    )

    quests_folder = {
        "HandleId": quests_handle,
        "Data": {
            "$type": "gameJournalPrimaryFolderEntry",
            "id": "quests",
            "journalEntryOverrideDataList": [],
            "entries": [
                {
                    "HandleId": side_quest_handle,
                    "Data": {
                        "$type": "gameJournalFolderEntry",
                        "id": "side_quest",
                        "journalEntryOverrideDataList": [],
                        "entries": [quest_ep00_node, quest_ep01_node, quest_ep02_node, quest_ep03_node, quest_ep04_node, quest_ep05_node],
                    },
                }
            ],
        },
    }

    contacts_handle = hc.next()

    def msg_node(mid: str, sender: str, text_key: str, important: int = 0) -> dict[str, Any]:
        return make_node(
            "gameJournalPhoneMessage",
            attachment=None,
            delay=0,
            id=mid,
            imageId=_tdb_uint0(),
            isQuestImportant=important,
            journalEntryOverrideDataList=[],
            sender=sender,
            text=_loc_val(text_key),
        )

    def choice_node(cid: str, text_key: str) -> dict[str, Any]:
        return make_node(
            "gameJournalPhoneChoiceEntry",
            id=cid,
            isQuestImportant=1,
            journalEntryOverrideDataList=[],
            questCondition=None,
            text=_loc_val(text_key),
        )

    chispa_h = hc.next()
    conv_ep00_h = hc.next()
    msg_hook = msg_node("msg_ep00_hook", "NPC", "ch_sms_ep00_hook", important=1)
    cg_h = hc.next()
    c1 = choice_node("reply_century", "ch_sms_choice_century")
    c2 = choice_node("reply_coords", "ch_sms_choice_coords")
    choice_group = {
        "HandleId": cg_h,
        "Data": {
            "$type": "gameJournalPhoneChoiceGroup",
            "entries": [c1, c2],
            "id": "choices_ep00",
            "journalEntryOverrideDataList": [],
        },
    }
    conv_entries = [
        msg_hook,
        choice_group,
        msg_node("msg_ep00_century", "NPC", "ch_sms_reply_century", important=1),
        msg_node("msg_ep00_coords", "NPC", "ch_sms_reply_coords", important=1),
        msg_node("msg_ep00_summary", "NPC", "ch_sms_ep00_summary"),
    ]

    conv_ep01_h = hc.next()
    cg_ep01_h = hc.next()
    ep01_c1 = choice_node("reply_ep01_ghost", "ch_sms_choice_ep01_ghost")
    ep01_c2 = choice_node("reply_ep01_scavs", "ch_sms_choice_ep01_scavs")
    conv_ep01_entries = [
        msg_node("msg_ep01_hook", "NPC", "ch_sms_ep01_hook", important=1),
        {
            "HandleId": cg_ep01_h,
            "Data": {
                "$type": "gameJournalPhoneChoiceGroup",
                "entries": [ep01_c1, ep01_c2],
                "id": "choices_ep01",
                "journalEntryOverrideDataList": [],
            },
        },
        msg_node("msg_ep01_ghost", "NPC", "ch_sms_reply_ep01_ghost", important=1),
        msg_node("msg_ep01_scavs", "NPC", "ch_sms_reply_ep01_scavs", important=1),
        msg_node("msg_ep01_summary", "NPC", "ch_sms_ep01_summary"),
    ]

    conv_ep02_h = hc.next()
    cg_ep02_h = hc.next()
    ep02_c1 = choice_node("reply_ep02_cult", "ch_sms_choice_ep02_cult")
    ep02_c2 = choice_node("reply_ep02_docks", "ch_sms_choice_ep02_docks")
    conv_ep02_entries = [
        msg_node("msg_ep02_hook", "NPC", "ch_sms_ep02_hook", important=1),
        {
            "HandleId": cg_ep02_h,
            "Data": {
                "$type": "gameJournalPhoneChoiceGroup",
                "entries": [ep02_c1, ep02_c2],
                "id": "choices_ep02",
                "journalEntryOverrideDataList": [],
            },
        },
        msg_node("msg_ep02_cult", "NPC", "ch_sms_reply_ep02_cult", important=1),
        msg_node("msg_ep02_docks", "NPC", "ch_sms_reply_ep02_docks", important=1),
        msg_node("msg_ep02_summary", "NPC", "ch_sms_ep02_summary"),
    ]

    conv_ep03_h = hc.next()
    cg_ep03_h = hc.next()
    ep03_c1 = choice_node("reply_ep03_claws", "ch_sms_choice_ep03_claws")
    ep03_c2 = choice_node("reply_ep03_quay", "ch_sms_choice_ep03_quay")
    conv_ep03_entries = [
        msg_node("msg_ep03_hook", "NPC", "ch_sms_ep03_hook", important=1),
        {
            "HandleId": cg_ep03_h,
            "Data": {
                "$type": "gameJournalPhoneChoiceGroup",
                "entries": [ep03_c1, ep03_c2],
                "id": "choices_ep03",
                "journalEntryOverrideDataList": [],
            },
        },
        msg_node("msg_ep03_claws", "NPC", "ch_sms_reply_ep03_claws", important=1),
        msg_node("msg_ep03_quay", "NPC", "ch_sms_reply_ep03_quay", important=1),
        msg_node("msg_ep03_summary", "NPC", "ch_sms_ep03_summary"),
    ]

    conv_ep04_h = hc.next()
    cg_ep04_h = hc.next()
    ep04_c1 = choice_node("reply_ep04_gangs", "ch_sms_choice_ep04_gangs")
    ep04_c2 = choice_node("reply_ep04_coords", "ch_sms_choice_ep04_coords")
    conv_ep04_entries = [
        msg_node("msg_ep04_hook", "NPC", "ch_sms_ep04_hook", important=1),
        {
            "HandleId": cg_ep04_h,
            "Data": {
                "$type": "gameJournalPhoneChoiceGroup",
                "entries": [ep04_c1, ep04_c2],
                "id": "choices_ep04",
                "journalEntryOverrideDataList": [],
            },
        },
        msg_node("msg_ep04_gangs", "NPC", "ch_sms_reply_ep04_gangs", important=1),
        msg_node("msg_ep04_coords", "NPC", "ch_sms_reply_ep04_coords", important=1),
        msg_node("msg_ep04_summary", "NPC", "ch_sms_ep04_summary"),
    ]

    conv_ep05_h = hc.next()
    cg_ep05_h = hc.next()
    ep05_c1 = choice_node("reply_ep05_voodoo", "ch_sms_choice_ep05_voodoo")
    ep05_c2 = choice_node("reply_ep05_pacifica", "ch_sms_choice_ep05_pacifica")
    conv_ep05_entries = [
        msg_node("msg_ep05_hook", "NPC", "ch_sms_ep05_hook", important=1),
        {
            "HandleId": cg_ep05_h,
            "Data": {
                "$type": "gameJournalPhoneChoiceGroup",
                "entries": [ep05_c1, ep05_c2],
                "id": "choices_ep05",
                "journalEntryOverrideDataList": [],
            },
        },
        msg_node("msg_ep05_voodoo", "NPC", "ch_sms_reply_ep05_voodoo", important=1),
        msg_node("msg_ep05_pacifica", "NPC", "ch_sms_reply_ep05_pacifica", important=1),
        msg_node("msg_ep05_summary", "NPC", "ch_sms_ep05_summary"),
    ]

    contact_chispa = {
        "HandleId": chispa_h,
        "Data": {
            "$type": "gameJournalContact",
            "avatarID": _tdb_str("PhoneAvatars.Avatar_Bartmoss"),
            "entries": [
                {
                    "HandleId": conv_ep00_h,
                    "Data": {
                        "$type": "gameJournalPhoneConversation",
                        "entries": conv_entries,
                        "id": "conv_ep00",
                        "journalEntryOverrideDataList": [],
                        "title": _loc_val("ch_conv_ep00_title"),
                    },
                },
                {
                    "HandleId": conv_ep01_h,
                    "Data": {
                        "$type": "gameJournalPhoneConversation",
                        "entries": conv_ep01_entries,
                        "id": "conv_ep01",
                        "journalEntryOverrideDataList": [],
                        "title": _loc_val("ch_conv_ep01_title"),
                    },
                },
                {
                    "HandleId": conv_ep02_h,
                    "Data": {
                        "$type": "gameJournalPhoneConversation",
                        "entries": conv_ep02_entries,
                        "id": "conv_ep02",
                        "journalEntryOverrideDataList": [],
                        "title": _loc_val("ch_conv_ep02_title"),
                    },
                },
                {
                    "HandleId": conv_ep03_h,
                    "Data": {
                        "$type": "gameJournalPhoneConversation",
                        "entries": conv_ep03_entries,
                        "id": "conv_ep03",
                        "journalEntryOverrideDataList": [],
                        "title": _loc_val("ch_conv_ep03_title"),
                    },
                },
                {
                    "HandleId": conv_ep04_h,
                    "Data": {
                        "$type": "gameJournalPhoneConversation",
                        "entries": conv_ep04_entries,
                        "id": "conv_ep04",
                        "journalEntryOverrideDataList": [],
                        "title": _loc_val("ch_conv_ep04_title"),
                    },
                },
                {
                    "HandleId": conv_ep05_h,
                    "Data": {
                        "$type": "gameJournalPhoneConversation",
                        "entries": conv_ep05_entries,
                        "id": "conv_ep05",
                        "journalEntryOverrideDataList": [],
                        "title": _loc_val("ch_conv_ep05_title"),
                    },
                },
            ],
            "id": "chispa_ai",
            "isCallableDefault": 0,
            "journalEntryOverrideDataList": [],
            "name": _loc_val("ch_contact_name"),
            "type": "Caller",
            "useFlatMessageLayout": 1,
        },
    }

    contacts_folder = {
        "HandleId": contacts_handle,
        "Data": {
            "$type": "gameJournalPrimaryFolderEntry",
            "id": "contacts",
            "journalEntryOverrideDataList": [],
            "entries": [contact_chispa],
        },
    }

    onscreens_h = hc.next()
    group_h = hc.next()
    shard00 = make_node(
        "gameJournalOnscreen",
        description=_loc_val("ch_shard_ep00_text"),
        iconID=_tdb_uint0(),
        id="chispa_shard_ep00",
        journalEntryOverrideDataList=[],
        tag={"$type": "CName", "$storage": "string", "$value": "quests"},
        title=_loc_val("ch_shard_ep00_title"),
    )
    shard01 = make_node(
        "gameJournalOnscreen",
        description=_loc_val("ch_shard_ep01_text"),
        iconID=_tdb_uint0(),
        id="chispa_shard_ep01",
        journalEntryOverrideDataList=[],
        tag={"$type": "CName", "$storage": "string", "$value": "quests"},
        title=_loc_val("ch_shard_ep01_title"),
    )
    shard02 = make_node(
        "gameJournalOnscreen",
        description=_loc_val("ch_shard_ep02_text"),
        iconID=_tdb_uint0(),
        id="chispa_shard_ep02",
        journalEntryOverrideDataList=[],
        tag={"$type": "CName", "$storage": "string", "$value": "quests"},
        title=_loc_val("ch_shard_ep02_title"),
    )
    shard03 = make_node(
        "gameJournalOnscreen",
        description=_loc_val("ch_shard_ep03_text"),
        iconID=_tdb_uint0(),
        id="chispa_shard_ep03",
        journalEntryOverrideDataList=[],
        tag={"$type": "CName", "$storage": "string", "$value": "quests"},
        title=_loc_val("ch_shard_ep03_title"),
    )
    shard04 = make_node(
        "gameJournalOnscreen",
        description=_loc_val("ch_shard_ep04_text"),
        iconID=_tdb_uint0(),
        id="chispa_shard_ep04",
        journalEntryOverrideDataList=[],
        tag={"$type": "CName", "$storage": "string", "$value": "quests"},
        title=_loc_val("ch_shard_ep04_title"),
    )
    shard05 = make_node(
        "gameJournalOnscreen",
        description=_loc_val("ch_shard_ep05_text"),
        iconID=_tdb_uint0(),
        id="chispa_shard_ep05",
        journalEntryOverrideDataList=[],
        tag={"$type": "CName", "$storage": "string", "$value": "quests"},
        title=_loc_val("ch_shard_ep05_title"),
    )
    onscreens_folder = {
        "HandleId": onscreens_h,
        "Data": {
            "$type": "gameJournalPrimaryFolderEntry",
            "id": "onscreens",
            "journalEntryOverrideDataList": [],
            "entries": [
                {
                    "HandleId": group_h,
                    "Data": {
                        "$type": "gameJournalOnscreenGroup",
                        "id": "chispa_shards",
                        "journalEntryOverrideDataList": [],
                        "entries": [shard00, shard01, shard02, shard03, shard04, shard05],
                    },
                }
            ],
        },
    }

    return {
        "Header": {
            "WolvenKitVersion": "9.1.1",
            "WKitJsonVersion": "0.0.9",
            "GameVersion": 2310,
            "ExportedDateTime": "2026-11-18T11:00:00.0000000Z",
            "DataType": "CR2W",
            "ArchiveFileName": "chispa_nc\\journal\\chispa_nc.journal",
        },
        "Data": {
            "Version": 195,
            "BuildVersion": 0,
            "RootChunk": {
                "$type": "gameJournalResource",
                "cookingPlatform": "PLATFORM_PC",
                "entry": {
                    "HandleId": root_handle,
                    "Data": {
                        "$type": "gameJournalRootFolderEntry",
                        "descriptor": {
                            "DepotPath": {
                                "$type": "ResourcePath",
                                "$storage": "string",
                                "$value": "base\\journal\\descriptor.journaldesc",
                            },
                            "Flags": "Soft",
                        },
                        "entries": [quests_folder, contacts_folder, onscreens_folder],
                    },
                },
            },
        },
    }


def build_localization_json(lang: str) -> dict[str, Any]:
    idx = 0 if lang == "en-us" else 1
    entries = [
        {
            "$type": "localizationPersistenceOnScreenEntry",
            "femaleVariant": pair[idx],
            "maleVariant": "",
            "primaryKey": "0",
            "secondaryKey": key,
        }
        for key, pair in LOC_STRINGS.items()
    ]
    return {
        "Header": {
            "WolvenKitVersion": "9.1.1",
            "WKitJsonVersion": "0.0.9",
            "GameVersion": 2310,
            "ExportedDateTime": "2026-11-18T11:00:00.0000000Z",
            "DataType": "CR2W",
            "ArchiveFileName": f"chispa_nc\\localization\\{lang}.json",
        },
        "Data": {
            "Version": 195,
            "BuildVersion": 0,
            "RootChunk": {
                "$type": "JsonResource",
                "cookingPlatform": "PLATFORM_PC",
                "root": {
                    "HandleId": "0",
                    "Data": {
                        "$type": "localizationPersistenceOnScreenEntries",
                        "entries": entries,
                    },
                },
            },
        },
    }


def main() -> None:
    journal_path = WK_ARCHIVE / "journal" / "chispa_nc.journal.json"
    en_path = WK_ARCHIVE / "localization" / "en-us.json.json"
    es_path = WK_ARCHIVE / "localization" / "es-es.json.json"

    journal_path.parent.mkdir(parents=True, exist_ok=True)
    en_path.parent.mkdir(parents=True, exist_ok=True)

    journal_path.write_text(json.dumps(build_journal_json(), indent=2, ensure_ascii=False), encoding="utf-8")
    en_path.write_text(json.dumps(build_localization_json("en-us"), indent=2, ensure_ascii=False), encoding="utf-8")
    es_path.write_text(json.dumps(build_localization_json("es-es"), indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"[OK] Journal -> {journal_path}")
    print(f"[OK] EN Loc  -> {en_path} ({len(LOC_STRINGS)} keys)")
    print(f"[OK] ES Loc  -> {es_path} ({len(LOC_STRINGS)} keys)")


if __name__ == "__main__":
    main()
