"""
Generates CR2W entity templates (.ent.json) for Protocolo CHISPA / SPARKY Protocol
using verified base-game meshes from hei_gui_stealth templates:
  - chispa_briefcase_rig.ent.json   (Waist-height ~1.07m Zetatech 2022 Briefcase Console)
  - chispa_dongle_shard.ent.json    (Extractable C.H.I.S.P.A. v0.98b Coprocessor Shard)
  - chispa_hazard_capacitor.ent.json (~1.12m Unstable Industrial Capacitor with electric glow)
"""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any

MOD_ROOT = Path(__file__).resolve().parent.parent
WORKSPACE_ROOT = MOD_ROOT.parent.parent
HEIGUI_ENT_DIR = WORKSPACE_ROOT / "mods" / "hei_gui_stealth" / "wolvenkit_src" / "archive" / "hei_gui_stealth" / "entities"
OUT_ENT_DIR = MOD_ROOT / "wolvenkit_src" / "archive" / "chispa_nc" / "entities"

MESH_TERMINAL_NEOMIL = "base\\environment\\decoration\\electronics\\devices\\device_data_terminal\\device_data_terminal_c_neomilitary.mesh"
MESH_CYBERDECK_BASE = "base\\environment\\decoration\\unique\\quest\\q108\\q108_cyberdeck\\q108_cyberdeck_a_base_a.mesh"
MESH_CYBERDECK_SCREEN = "base\\environment\\decoration\\unique\\quest\\q108\\q108_cyberdeck\\q108_cyberdeck_a_screen_a.mesh"
MESH_SHARD = "base\\environment\\decoration\\electronics\\hardware\\shard\\shard_a.mesh"
MESH_ELEC_BOX_D = "base\\environment\\decoration\\public_utility\\generator\\electrical_box\\electrical_box_d.mesh"
MESH_ELEC_BOX_H = "base\\environment\\decoration\\public_utility\\generator\\electrical_box\\electrical_box_h.mesh"
MESH_TERMINAL_ENTROPY = "base\\environment\\decoration\\electronics\\devices\\device_data_terminal\\device_data_terminal_a_entropy.mesh"
MESH_SERVICE_COMPUTER = "base\\environment\\decoration\\electronics\\service\\service_computer\\service_computer_b.mesh"
MESH_ANTENNA_MAST = "base\\environment\\decoration\\unique\\ow\\antenna_small_access_point\\antenna_small_access_point_entropy_a.mesh"
MESH_TERMINAL_KITSCH = "base\\environment\\decoration\\electronics\\devices\\device_data_terminal\\device_data_terminal_b_kitsch.mesh"
MESH_SURGICAL_MACHINE = "base\\environment\\decoration\\electronics\\medical\\surgical_machine\\surgical_machine_a.mesh"
MESH_CYBERWARE_POD = "base\\items\\interactive\\medical\\int_medical_002__cyberware_container\\int_medical_002__cyberware_container_01.mesh"
MESH_COMPUTER_STAND = "base\\environment\\decoration\\electronics\\hardware\\hardware_computer_stand\\hardware_computer_stand_a.mesh"
MESH_PACKING_CRATE_B = "base\\environment\\decoration\\containers\\crates\\packing_crates\\packing_crate_b.mesh"
MESH_PACKING_CRATE_B_LID = "base\\environment\\decoration\\containers\\crates\\packing_crates\\packing_crate_b_lid.mesh"
MESH_PACKING_CRATE_ARASAKA = "base\\environment\\decoration\\containers\\crates\\packing_crates\\packing_crate_b_decals_corpo.mesh"
MESH_HARDWARE_TERMINAL = "base\\environment\\decoration\\electronics\\hardware\\hardware_terminal\\hardware_terminal_a.mesh"
MESH_MILITARY_CASE_K = "base\\items\\interactive\\containers\\int_container_001__military_case_k\\int_container_001__military_case_k.mesh"
MESH_ANTENNA_NEOMIL = "base\\environment\\decoration\\unique\\ow\\antenna_small_access_point\\antenna_small_access_point_neomilitary_b.mesh"
MESH_PACKING_CRATE_A = "base\\environment\\decoration\\containers\\crates\\packing_crates\\packing_crate_a.mesh"
MESH_MILITARY_CASE_D = "base\\environment\\decoration\\containers\\cases\\military_case\\military_case_d.mesh"
MESH_MILITARY_CASE_H = "base\\environment\\decoration\\containers\\cases\\military_case\\military_case_h.mesh"
MESH_ROAD_BARRIER_B = "base\\environment\\decoration\\public_utility\\roadblock\\road_barrier\\road_barrier_b.mesh"


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _sync_redpackage_and_deps(
    doc: dict[str, Any],
    archive_file_name: str,
    components: list[dict[str, Any]],
    meshes: list[str],
) -> dict[str, Any]:
    doc["Header"]["ArchiveFileName"] = archive_file_name
    root = doc["Data"]["RootChunk"]
    game_obj = root["compiledData"]["Data"]["Chunks"][0]

    cruid_dict: dict[str, str] = {"0": "0"}
    chunks: list[dict[str, Any]] = [copy.deepcopy(game_obj)]
    for idx, comp in enumerate(components, start=1):
        cruid_dict[str(idx)] = str(comp["id"])
        chunks.append(copy.deepcopy(comp))

    pkg = root["compiledData"]["Data"]
    pkg["CruidDict"] = cruid_dict
    pkg["Chunks"] = chunks
    root["components"] = copy.deepcopy(components)
    root["resolvedDependencies"] = [
        {
            "DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": m},
            "Flags": "Soft",
        }
        for m in meshes
    ]
    return doc


def _set_fixed_pos(comp: dict[str, Any], x_bits: int, y_bits: int, z_bits: int) -> None:
    pos = comp["localTransform"]["Position"]
    pos["x"]["Bits"] = x_bits
    pos["y"]["Bits"] = y_bits
    pos["z"]["Bits"] = z_bits


def _set_scale(comp: dict[str, Any], sx: float, sy: float, sz: float) -> None:
    comp["visualScale"]["X"] = sx
    comp["visualScale"]["Y"] = sy
    comp["visualScale"]["Z"] = sz


def _set_mesh(comp: dict[str, Any], mesh_path: str, appearance: str = "default") -> None:
    comp["mesh"]["DepotPath"]["$value"] = mesh_path
    comp["meshAppearance"]["$value"] = appearance


def _set_light(
    comp: dict[str, Any],
    name: str,
    cid: str,
    r: int,
    g: int,
    b: int,
    intensity: int,
    radius: float,
    z_bits: int,
) -> None:
    comp["id"] = cid
    comp["name"]["$value"] = name
    comp["color"]["Red"] = r
    comp["color"]["Green"] = g
    comp["color"]["Blue"] = b
    comp["color"]["Alpha"] = 255
    comp["intensity"] = intensity
    comp["radius"] = radius
    _set_fixed_pos(comp, 0, 0, z_bits)


def build_entities() -> None:
    OUT_ENT_DIR.mkdir(parents=True, exist_ok=True)
    case_tmpl = _load_json(HEIGUI_ENT_DIR / "heigui_dead_drop_case.ent.json")
    shard_tmpl = _load_json(HEIGUI_ENT_DIR / "heigui_dead_drop_shard.ent.json")

    base_comps = case_tmpl["Data"]["RootChunk"]["components"]
    shard_comps = shard_tmpl["Data"]["RootChunk"]["components"]

    # 1. chispa_briefcase_rig.ent.json (Neomilitary Data Terminal 1.33m tall — distinct from generic cases)
    b1 = copy.deepcopy(base_comps[0])
    b1["id"] = "9300000000000000001"
    b1["name"]["$value"] = "ch_console_terminal_body"
    _set_mesh(b1, MESH_TERMINAL_NEOMIL, "clean_a")
    _set_scale(b1, 1.0, 1.0, 1.0)
    _set_fixed_pos(b1, 0, 0, 0)

    b2 = copy.deepcopy(base_comps[2])
    _set_light(b2, "ch_console_amber_glow", "9300000000000000004", 255, 165, 50, 95, 4.0, 182000)

    b3 = copy.deepcopy(base_comps[3])
    _set_light(b3, "ch_console_cyan_key", "9300000000000000005", 45, 225, 255, 75, 3.2, 155000)

    briefcase_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_briefcase_rig.ent",
        [b1, b2, b3],
        [MESH_TERMINAL_NEOMIL],
    )
    (OUT_ENT_DIR / "chispa_briefcase_rig.ent.json").write_text(json.dumps(briefcase_doc, indent=2), encoding="utf-8")

    # 2. chispa_dongle_shard.ent.json (Extractable orange q108 cyberdeck + shard atop terminal, despawns on pickup)
    s1 = copy.deepcopy(shard_comps[0])
    s1["id"] = "9300000000000000011"
    s1["name"]["$value"] = "ch_dongle_deck_base"
    _set_mesh(s1, MESH_CYBERDECK_BASE, "orange")
    _set_scale(s1, 1.60, 1.60, 1.60)
    _set_fixed_pos(s1, -18000, 0, 174850)

    s2 = copy.deepcopy(shard_comps[0])
    s2["id"] = "9300000000000000013"
    s2["name"]["$value"] = "ch_dongle_deck_screen"
    _set_mesh(s2, MESH_CYBERDECK_SCREEN, "orange")
    _set_scale(s2, 1.60, 1.60, 1.60)
    _set_fixed_pos(s2, -18000, 0, 176500)

    s3 = copy.deepcopy(shard_comps[0])
    s3["id"] = "9300000000000000014"
    s3["name"]["$value"] = "ch_dongle_shard_mesh"
    _set_mesh(s3, MESH_SHARD, "default")
    _set_scale(s3, 1.25, 1.25, 1.25)
    _set_fixed_pos(s3, 4000, 0, 180500)

    s4 = copy.deepcopy(shard_comps[1])
    _set_light(s4, "ch_dongle_shard_light", "9300000000000000012", 255, 195, 45, 180, 4.5, 192000)

    dongle_doc = _sync_redpackage_and_deps(
        copy.deepcopy(shard_tmpl),
        "chispa_nc\\entities\\chispa_dongle_shard.ent",
        [s1, s2, s3, s4],
        [MESH_CYBERDECK_BASE, MESH_CYBERDECK_SCREEN, MESH_SHARD],
    )
    (OUT_ENT_DIR / "chispa_dongle_shard.ent.json").write_text(json.dumps(dongle_doc, indent=2), encoding="utf-8")

    # 3. chispa_hazard_capacitor.ent.json (Unstable electrical generator + yellow relay pylon)
    k1 = copy.deepcopy(base_comps[0])
    k1["id"] = "9300000000000000021"
    k1["name"]["$value"] = "ch_cap_generator_main"
    _set_mesh(k1, MESH_ELEC_BOX_D, "default")
    _set_scale(k1, 1.0, 1.0, 1.0)
    _set_fixed_pos(k1, 0, 0, 0)

    k2 = copy.deepcopy(base_comps[0])
    k2["id"] = "9300000000000000022"
    k2["name"]["$value"] = "ch_cap_relay_pylon"
    _set_mesh(k2, MESH_ELEC_BOX_H, "yellow")
    _set_scale(k2, 1.0, 1.0, 1.0)
    _set_fixed_pos(k2, -100000, 6500, 0)

    k3 = copy.deepcopy(base_comps[2])
    _set_light(k3, "ch_cap_arc_glow", "9300000000000000024", 30, 160, 255, 240, 6.0, 158000)

    k4 = copy.deepcopy(base_comps[3])
    _set_light(k4, "ch_cap_spark_core", "9300000000000000025", 160, 235, 255, 130, 3.5, 142000)

    cap_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_hazard_capacitor.ent",
        [k1, k2, k3, k4],
        [MESH_ELEC_BOX_D, MESH_ELEC_BOX_H],
    )
    (OUT_ENT_DIR / "chispa_hazard_capacitor.ent.json").write_text(json.dumps(cap_doc, indent=2), encoding="utf-8")

    # 4. chispa_ep01_entropy_terminal.ent.json (Ep. 1 Entropy data terminal 1.32m tall)
    e1 = copy.deepcopy(base_comps[0])
    e1["id"] = "9300000000000000031"
    e1["name"]["$value"] = "ch_ep01_term_body"
    _set_mesh(e1, MESH_TERMINAL_ENTROPY, "clean_a")
    _set_scale(e1, 1.0, 1.0, 1.0)
    _set_fixed_pos(e1, 0, 0, 0)

    e2 = copy.deepcopy(base_comps[2])
    _set_light(e2, "ch_ep01_term_cyan", "9300000000000000032", 40, 220, 255, 105, 4.0, 180000)

    e3 = copy.deepcopy(base_comps[3])
    _set_light(e3, "ch_ep01_term_violet", "9300000000000000033", 165, 90, 255, 85, 3.4, 150000)

    ep01_term_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep01_entropy_terminal.ent",
        [e1, e2, e3],
        [MESH_TERMINAL_ENTROPY],
    )
    (OUT_ENT_DIR / "chispa_ep01_entropy_terminal.ent.json").write_text(json.dumps(ep01_term_doc, indent=2), encoding="utf-8")

    # 5. chispa_ep01_sector_module.ent.json (Extractable cyberspace q108 cyberdeck + shard atop Entropy terminal)
    m1 = copy.deepcopy(shard_comps[0])
    m1["id"] = "9300000000000000041"
    m1["name"]["$value"] = "ch_ep01_sec_deck_base"
    _set_mesh(m1, MESH_CYBERDECK_BASE, "cyberspace")
    _set_scale(m1, 1.60, 1.60, 1.60)
    _set_fixed_pos(m1, -16000, 0, 173500)

    m2 = copy.deepcopy(shard_comps[0])
    m2["id"] = "9300000000000000042"
    m2["name"]["$value"] = "ch_ep01_sec_deck_screen"
    _set_mesh(m2, MESH_CYBERDECK_SCREEN, "cyberspace")
    _set_scale(m2, 1.60, 1.60, 1.60)
    _set_fixed_pos(m2, -16000, 0, 175200)

    m3 = copy.deepcopy(shard_comps[0])
    m3["id"] = "9300000000000000043"
    m3["name"]["$value"] = "ch_ep01_sec_shard"
    _set_mesh(m3, MESH_SHARD, "default")
    _set_scale(m3, 1.25, 1.25, 1.25)
    _set_fixed_pos(m3, 5000, 0, 179500)

    m4 = copy.deepcopy(shard_comps[1])
    _set_light(m4, "ch_ep01_sec_light", "9300000000000000044", 55, 230, 255, 185, 4.5, 191000)

    ep01_sec_doc = _sync_redpackage_and_deps(
        copy.deepcopy(shard_tmpl),
        "chispa_nc\\entities\\chispa_ep01_sector_module.ent",
        [m1, m2, m3, m4],
        [MESH_CYBERDECK_BASE, MESH_CYBERDECK_SCREEN, MESH_SHARD],
    )
    (OUT_ENT_DIR / "chispa_ep01_sector_module.ent.json").write_text(json.dumps(ep01_sec_doc, indent=2), encoding="utf-8")

    # 6. chispa_ep01_relay_node.ent.json (Tall red service computer ~2.11m scaled 0.92 — RABIDS Relay Node)
    r1 = copy.deepcopy(base_comps[0])
    r1["id"] = "9300000000000000051"
    r1["name"]["$value"] = "ch_ep01_relay_body"
    _set_mesh(r1, MESH_SERVICE_COMPUTER, "red")
    _set_scale(r1, 0.92, 0.92, 0.92)
    _set_fixed_pos(r1, 0, 0, 0)

    r2 = copy.deepcopy(base_comps[2])
    _set_light(r2, "ch_ep01_relay_red", "9300000000000000052", 255, 70, 55, 145, 4.2, 245000)

    r3 = copy.deepcopy(base_comps[3])
    _set_light(r3, "ch_ep01_relay_cyan", "9300000000000000053", 40, 225, 255, 115, 3.6, 175000)

    ep01_relay_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep01_relay_node.ent",
        [r1, r2, r3],
        [MESH_SERVICE_COMPUTER],
    )
    (OUT_ENT_DIR / "chispa_ep01_relay_node.ent.json").write_text(json.dumps(ep01_relay_doc, indent=2), encoding="utf-8")

    # 7. chispa_ep01_cam_mast.ent.json (Antenna mast ~3.17m tall scaled 0.65 supporting surveillance cameras)
    a1 = copy.deepcopy(base_comps[0])
    a1["id"] = "9300000000000000061"
    a1["name"]["$value"] = "ch_ep01_cam_mast_body"
    _set_mesh(a1, MESH_ANTENNA_MAST, "default")
    _set_scale(a1, 0.65, 0.65, 0.65)
    _set_fixed_pos(a1, 0, 0, 0)

    a2 = copy.deepcopy(base_comps[2])
    _set_light(a2, "ch_ep01_cam_mast_pilot", "9300000000000000062", 255, 140, 40, 65, 2.8, 360000)

    ep01_mast_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep01_cam_mast.ent",
        [a1, a2],
        [MESH_ANTENNA_MAST],
    )
    (OUT_ENT_DIR / "chispa_ep01_cam_mast.ent.json").write_text(json.dumps(ep01_mast_doc, indent=2), encoding="utf-8")

    # 8. chispa_ep02_maelstrom_rig.ent.json (Kitsch Terminal 1.41m + Black Pylon + Surgical Machine atop)
    r01 = copy.deepcopy(base_comps[0])
    r01["id"] = "9300000000000000071"
    r01["name"]["$value"] = "ch_ep02_rig_terminal"
    _set_mesh(r01, MESH_TERMINAL_KITSCH, "clean_a")
    _set_scale(r01, 1.0, 1.0, 1.0)
    _set_fixed_pos(r01, 0, 0, 0)

    r02 = copy.deepcopy(base_comps[0])
    r02["id"] = "9300000000000000072"
    r02["name"]["$value"] = "ch_ep02_rig_pedestal"
    _set_mesh(r02, MESH_ELEC_BOX_H, "black")
    _set_scale(r02, 1.0, 1.0, 1.0)
    _set_fixed_pos(r02, 102236, -5243, 0)

    r03 = copy.deepcopy(base_comps[0])
    r03["id"] = "9300000000000000073"
    r03["name"]["$value"] = "ch_ep02_rig_surgical"
    _set_mesh(r03, MESH_SURGICAL_MACHINE, "default")
    _set_scale(r03, 1.0, 1.0, 1.0)
    _set_fixed_pos(r03, 102236, -5243, 144179)

    r04 = copy.deepcopy(base_comps[2])
    _set_light(r04, "ch_ep02_rig_red", "9300000000000000074", 255, 50, 60, 120, 4.2, 192000)

    r05 = copy.deepcopy(base_comps[3])
    _set_light(r05, "ch_ep02_rig_amber", "9300000000000000075", 255, 175, 45, 90, 3.5, 165000)

    ep02_rig_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep02_maelstrom_rig.ent",
        [r01, r02, r03, r04, r05],
        [MESH_TERMINAL_KITSCH, MESH_ELEC_BOX_H, MESH_SURGICAL_MACHINE],
    )
    (OUT_ENT_DIR / "chispa_ep02_maelstrom_rig.ent.json").write_text(json.dumps(ep02_rig_doc, indent=2), encoding="utf-8")

    # 9. chispa_ep02_sector_module.ent.json (Extractable cyberware pod + shard atop Kitsch Terminal)
    p01 = copy.deepcopy(shard_comps[0])
    p01["id"] = "9300000000000000081"
    p01["name"]["$value"] = "ch_ep02_sec_pod"
    _set_mesh(p01, MESH_CYBERWARE_POD, "default")
    _set_scale(p01, 1.65, 1.65, 1.65)
    _set_fixed_pos(p01, -12000, 0, 184156)

    p02 = copy.deepcopy(shard_comps[0])
    p02["id"] = "9300000000000000082"
    p02["name"]["$value"] = "ch_ep02_sec_shard"
    _set_mesh(p02, MESH_SHARD, "default")
    _set_scale(p02, 1.30, 1.30, 1.30)
    _set_fixed_pos(p02, 14000, 0, 186000)

    p03 = copy.deepcopy(shard_comps[1])
    _set_light(p03, "ch_ep02_sec_light", "9300000000000000083", 255, 120, 40, 190, 4.6, 205000)

    ep02_sec_doc = _sync_redpackage_and_deps(
        copy.deepcopy(shard_tmpl),
        "chispa_nc\\entities\\chispa_ep02_sector_module.ent",
        [p01, p02, p03],
        [MESH_CYBERWARE_POD, MESH_SHARD],
    )
    (OUT_ENT_DIR / "chispa_ep02_sector_module.ent.json").write_text(json.dumps(ep02_sec_doc, indent=2), encoding="utf-8")

    # 10. chispa_ep02_power_regulator.ent.json (CHOOH2 Regulator Hardware Stand ~1.98m tall scaled 0.76)
    g01 = copy.deepcopy(base_comps[0])
    g01["id"] = "9300000000000000091"
    g01["name"]["$value"] = "ch_ep02_reg_stand"
    _set_mesh(g01, MESH_COMPUTER_STAND, "default")
    _set_scale(g01, 0.76, 0.76, 0.76)
    _set_fixed_pos(g01, 0, 0, 0)

    g02 = copy.deepcopy(base_comps[2])
    _set_light(g02, "ch_ep02_reg_red", "9300000000000000092", 255, 55, 45, 155, 4.5, 225000)

    g03 = copy.deepcopy(base_comps[3])
    _set_light(g03, "ch_ep02_reg_cyan", "9300000000000000093", 45, 215, 255, 120, 3.6, 145000)

    ep02_reg_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep02_power_regulator.ent",
        [g01, g02, g03],
        [MESH_COMPUTER_STAND],
    )
    (OUT_ENT_DIR / "chispa_ep02_power_regulator.ent.json").write_text(json.dumps(ep02_reg_doc, indent=2), encoding="utf-8")

    # 11. chispa_ep02_turret_plinth.ent.json (Black electrical box plinth ~1.045m tall supporting automated turret)
    t01 = copy.deepcopy(base_comps[0])
    t01["id"] = "9300000000000000101"
    t01["name"]["$value"] = "ch_ep02_plinth_body"
    _set_mesh(t01, MESH_ELEC_BOX_H, "black")
    _set_scale(t01, 1.25, 1.25, 0.95)
    _set_fixed_pos(t01, 0, 0, 0)

    t02 = copy.deepcopy(base_comps[2])
    _set_light(t02, "ch_ep02_plinth_red", "9300000000000000102", 255, 40, 40, 95, 3.2, 135000)

    ep02_plinth_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep02_turret_plinth.ent",
        [t01, t02],
        [MESH_ELEC_BOX_H],
    )
    (OUT_ENT_DIR / "chispa_ep02_turret_plinth.ent.json").write_text(json.dumps(ep02_plinth_doc, indent=2), encoding="utf-8")

    # 12. chispa_ep03_arasaka_rig.ent.json (Black Arasaka Packing Crate + Dark-Red Lid + Hardware Terminal)
    k01 = copy.deepcopy(base_comps[0])
    k01["id"] = "9300000000000000111"
    k01["name"]["$value"] = "ch_ep03_crate_body"
    _set_mesh(k01, MESH_PACKING_CRATE_B, "black")
    _set_scale(k01, 1.0, 1.0, 1.0)
    _set_fixed_pos(k01, 0, 0, 0)

    k02 = copy.deepcopy(base_comps[0])
    k02["id"] = "9300000000000000112"
    k02["name"]["$value"] = "ch_ep03_crate_lid"
    _set_mesh(k02, MESH_PACKING_CRATE_B_LID, "red_dark")
    _set_scale(k02, 1.0, 1.0, 1.0)
    _set_fixed_pos(k02, 0, 0, 63046)

    k03 = copy.deepcopy(base_comps[0])
    k03["id"] = "9300000000000000113"
    k03["name"]["$value"] = "ch_ep03_crate_decals"
    _set_mesh(k03, MESH_PACKING_CRATE_ARASAKA, "corpo_decals_arasaka")
    _set_scale(k03, 1.0, 1.0, 1.0)
    _set_fixed_pos(k03, 0, 0, 0)

    k04 = copy.deepcopy(base_comps[0])
    k04["id"] = "9300000000000000114"
    k04["name"]["$value"] = "ch_ep03_hw_terminal"
    _set_mesh(k04, MESH_HARDWARE_TERMINAL, "default")
    _set_scale(k04, 1.0, 1.0, 1.0)
    _set_fixed_pos(k04, 77332, -6554, 0)

    k05 = copy.deepcopy(base_comps[2])
    _set_light(k05, "ch_ep03_rig_crimson", "9300000000000000115", 255, 35, 55, 135, 4.4, 135000)

    k06 = copy.deepcopy(base_comps[3])
    _set_light(k06, "ch_ep03_rig_cyan", "9300000000000000116", 50, 220, 255, 95, 3.5, 155000)

    ep03_rig_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep03_arasaka_rig.ent",
        [k01, k02, k03, k04, k05, k06],
        [MESH_PACKING_CRATE_B, MESH_PACKING_CRATE_B_LID, MESH_PACKING_CRATE_ARASAKA, MESH_HARDWARE_TERMINAL],
    )
    (OUT_ENT_DIR / "chispa_ep03_arasaka_rig.ent.json").write_text(json.dumps(ep03_rig_doc, indent=2), encoding="utf-8")

    # 13. chispa_ep03_sector_module.ent.json (Extractable Arasaka Military Case + Shard atop Crate)
    m01 = copy.deepcopy(shard_comps[0])
    m01["id"] = "9300000000000000121"
    m01["name"]["$value"] = "ch_ep03_sec_case"
    _set_mesh(m01, MESH_MILITARY_CASE_K, "default_LED_RED")
    _set_scale(m01, 1.15, 1.15, 1.15)
    _set_fixed_pos(m01, -8000, 0, 73800)

    m02 = copy.deepcopy(shard_comps[0])
    m02["id"] = "9300000000000000122"
    m02["name"]["$value"] = "ch_ep03_sec_shard"
    _set_mesh(m02, MESH_SHARD, "default")
    _set_scale(m02, 1.30, 1.30, 1.30)
    _set_fixed_pos(m02, 12000, 0, 74500)

    m03 = copy.deepcopy(shard_comps[1])
    _set_light(m03, "ch_ep03_sec_light", "9300000000000000123", 255, 85, 65, 185, 4.5, 105000)

    ep03_sec_doc = _sync_redpackage_and_deps(
        copy.deepcopy(shard_tmpl),
        "chispa_nc\\entities\\chispa_ep03_sector_module.ent",
        [m01, m02, m03],
        [MESH_MILITARY_CASE_K, MESH_SHARD],
    )
    (OUT_ENT_DIR / "chispa_ep03_sector_module.ent.json").write_text(json.dumps(ep03_sec_doc, indent=2), encoding="utf-8")

    # 14. chispa_ep03_jammer_pylon.ent.json (Neomilitary IFF Smart-Jammer Access Pylon ~4.1m scaled 0.78)
    j01 = copy.deepcopy(base_comps[0])
    j01["id"] = "9300000000000000131"
    j01["name"]["$value"] = "ch_ep03_pylon_mast"
    _set_mesh(j01, MESH_ANTENNA_NEOMIL, "default_device")
    _set_scale(j01, 0.82, 0.82, 0.78)
    _set_fixed_pos(j01, 0, 0, 0)

    j02 = copy.deepcopy(base_comps[2])
    _set_light(j02, "ch_ep03_pylon_crimson", "9300000000000000132", 255, 30, 70, 155, 4.5, 215000)

    j03 = copy.deepcopy(base_comps[3])
    _set_light(j03, "ch_ep03_pylon_violet", "9300000000000000133", 220, 50, 255, 115, 3.6, 135000)

    ep03_pylon_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep03_jammer_pylon.ent",
        [j01, j02, j03],
        [MESH_ANTENNA_NEOMIL],
    )
    (OUT_ENT_DIR / "chispa_ep03_jammer_pylon.ent.json").write_text(json.dumps(ep03_pylon_doc, indent=2), encoding="utf-8")

    # 15. chispa_ep04_smuggler_rig.ent.json (Ep. 4 6th Street/Valentinos border smuggler crate + military case)
    c401 = copy.deepcopy(base_comps[0])
    c401["id"] = "9300000000000000141"
    c401["name"]["$value"] = "ch_ep04_rig_crate"
    _set_mesh(c401, MESH_PACKING_CRATE_A, "green_dark")
    _set_scale(c401, 1.0, 1.0, 1.0)
    _set_fixed_pos(c401, 0, 0, 0)

    c402 = copy.deepcopy(base_comps[0])
    c402["id"] = "9300000000000000142"
    c402["name"]["$value"] = "ch_ep04_rig_case"
    _set_mesh(c402, MESH_MILITARY_CASE_D, "device")
    _set_scale(c402, 1.0, 1.0, 1.0)
    _set_fixed_pos(c402, 88000, 0, 0)

    c403 = copy.deepcopy(base_comps[2])
    _set_light(c403, "ch_ep04_rig_gold", "9300000000000000143", 255, 190, 55, 130, 4.2, 145000)

    c404 = copy.deepcopy(base_comps[3])
    _set_light(c404, "ch_ep04_rig_green", "9300000000000000144", 95, 255, 110, 95, 3.5, 125000)

    ep04_rig_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep04_smuggler_rig.ent",
        [c401, c402, c403, c404],
        [MESH_PACKING_CRATE_A, MESH_MILITARY_CASE_D],
    )
    (OUT_ENT_DIR / "chispa_ep04_smuggler_rig.ent.json").write_text(json.dumps(ep04_rig_doc, indent=2), encoding="utf-8")

    # 16. chispa_ep04_sector_module.ent.json (Extractable military case_h + screen + shard atop green_dark crate)
    m401 = copy.deepcopy(shard_comps[0])
    m401["id"] = "9300000000000000151"
    m401["name"]["$value"] = "ch_ep04_sec_case"
    _set_mesh(m401, MESH_MILITARY_CASE_H, "default")
    _set_scale(m401, 0.95, 0.95, 0.95)
    _set_fixed_pos(m401, -8000, 0, 125900)

    m402 = copy.deepcopy(shard_comps[0])
    m402["id"] = "9300000000000000152"
    m402["name"]["$value"] = "ch_ep04_sec_screen"
    _set_mesh(m402, MESH_CYBERDECK_SCREEN, "default")
    _set_scale(m402, 1.50, 1.50, 1.50)
    _set_fixed_pos(m402, -8000, 0, 162500)

    m403 = copy.deepcopy(shard_comps[0])
    m403["id"] = "9300000000000000153"
    m403["name"]["$value"] = "ch_ep04_sec_shard"
    _set_mesh(m403, MESH_SHARD, "default")
    _set_scale(m403, 1.30, 1.30, 1.30)
    _set_fixed_pos(m403, 14000, 0, 128000)

    m404 = copy.deepcopy(shard_comps[1])
    _set_light(m404, "ch_ep04_sec_light", "9300000000000000154", 155, 255, 85, 185, 4.5, 168000)

    ep04_sec_doc = _sync_redpackage_and_deps(
        copy.deepcopy(shard_tmpl),
        "chispa_nc\\entities\\chispa_ep04_sector_module.ent",
        [m401, m402, m403, m404],
        [MESH_MILITARY_CASE_H, MESH_CYBERDECK_SCREEN, MESH_SHARD],
    )
    (OUT_ENT_DIR / "chispa_ep04_sector_module.ent.json").write_text(json.dumps(ep04_sec_doc, indent=2), encoding="utf-8")

    # 17. chispa_ep04_ballistic_relay.ent.json (Ep. 4 ballistic relay + road barrier)
    r401 = copy.deepcopy(base_comps[0])
    r401["id"] = "9300000000000000161"
    r401["name"]["$value"] = "ch_ep04_relay_box"
    _set_mesh(r401, MESH_ELEC_BOX_D, "black")
    _set_scale(r401, 0.88, 0.88, 0.88)
    _set_fixed_pos(r401, 0, 0, 0)

    r402 = copy.deepcopy(base_comps[0])
    r402["id"] = "9300000000000000162"
    r402["name"]["$value"] = "ch_ep04_relay_barrier"
    _set_mesh(r402, MESH_ROAD_BARRIER_B, "green")
    _set_scale(r402, 0.90, 0.90, 0.90)
    _set_fixed_pos(r402, 0, -48000, 0)

    r403 = copy.deepcopy(base_comps[2])
    _set_light(r403, "ch_ep04_relay_amber", "9300000000000000163", 255, 155, 40, 150, 4.4, 155000)

    r404 = copy.deepcopy(base_comps[3])
    _set_light(r404, "ch_ep04_relay_red", "9300000000000000164", 255, 45, 45, 115, 3.5, 125000)

    ep04_relay_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep04_ballistic_relay.ent",
        [r401, r402, r403, r404],
        [MESH_ELEC_BOX_D, MESH_ROAD_BARRIER_B],
    )
    (OUT_ENT_DIR / "chispa_ep04_ballistic_relay.ent.json").write_text(json.dumps(ep04_relay_doc, indent=2), encoding="utf-8")

    # 18. chispa_ep05_blackwall_rig.ent.json (Ep. 5 white service computer + blue crate + hardware terminal)
    b501 = copy.deepcopy(base_comps[0])
    b501["id"] = "9300000000000000171"
    b501["name"]["$value"] = "ch_ep05_rig_server"
    _set_mesh(b501, MESH_SERVICE_COMPUTER, "white")
    _set_scale(b501, 0.95, 0.95, 0.95)
    _set_fixed_pos(b501, -75000, 0, 0)

    b502 = copy.deepcopy(base_comps[0])
    b502["id"] = "9300000000000000172"
    b502["name"]["$value"] = "ch_ep05_rig_crate"
    _set_mesh(b502, MESH_PACKING_CRATE_A, "blue")
    _set_scale(b502, 1.0, 1.0, 1.0)
    _set_fixed_pos(b502, 0, 0, 0)

    b503 = copy.deepcopy(base_comps[0])
    b503["id"] = "9300000000000000173"
    b503["name"]["$value"] = "ch_ep05_rig_term"
    _set_mesh(b503, MESH_HARDWARE_TERMINAL, "default")
    _set_scale(b503, 1.0, 1.0, 1.0)
    _set_fixed_pos(b503, 82000, -6000, 0)

    b504 = copy.deepcopy(base_comps[2])
    _set_light(b504, "ch_ep05_rig_blackwall", "9300000000000000174", 255, 25, 65, 150, 4.8, 185000)

    b505 = copy.deepcopy(base_comps[3])
    _set_light(b505, "ch_ep05_rig_cyberspace", "9300000000000000175", 35, 235, 255, 125, 4.0, 140000)

    ep05_rig_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep05_blackwall_rig.ent",
        [b501, b502, b503, b504, b505],
        [MESH_SERVICE_COMPUTER, MESH_PACKING_CRATE_A, MESH_HARDWARE_TERMINAL],
    )
    (OUT_ENT_DIR / "chispa_ep05_blackwall_rig.ent.json").write_text(json.dumps(ep05_rig_doc, indent=2), encoding="utf-8")

    # 19. chispa_ep05_master_sector.ent.json (Extractable cyberspace deck + shard atop blue crate)
    s501 = copy.deepcopy(shard_comps[0])
    s501["id"] = "9300000000000000181"
    s501["name"]["$value"] = "ch_ep05_sec_deck_base"
    _set_mesh(s501, MESH_CYBERDECK_BASE, "cyberspace")
    _set_scale(s501, 1.75, 1.75, 1.75)
    _set_fixed_pos(s501, 0, 0, 126500)

    s502 = copy.deepcopy(shard_comps[0])
    s502["id"] = "9300000000000000182"
    s502["name"]["$value"] = "ch_ep05_sec_deck_screen"
    _set_mesh(s502, MESH_CYBERDECK_SCREEN, "cyberspace")
    _set_scale(s502, 1.75, 1.75, 1.75)
    _set_fixed_pos(s502, 0, 0, 128500)

    s503 = copy.deepcopy(shard_comps[0])
    s503["id"] = "9300000000000000183"
    s503["name"]["$value"] = "ch_ep05_sec_shard"
    _set_mesh(s503, MESH_SHARD, "default")
    _set_scale(s503, 1.40, 1.40, 1.40)
    _set_fixed_pos(s503, 16000, 0, 132000)

    s504 = copy.deepcopy(shard_comps[1])
    _set_light(s504, "ch_ep05_sec_light", "9300000000000000184", 55, 245, 255, 210, 5.0, 165000)

    ep05_sec_doc = _sync_redpackage_and_deps(
        copy.deepcopy(shard_tmpl),
        "chispa_nc\\entities\\chispa_ep05_master_sector.ent",
        [s501, s502, s503, s504],
        [MESH_CYBERDECK_BASE, MESH_CYBERDECK_SCREEN, MESH_SHARD],
    )
    (OUT_ENT_DIR / "chispa_ep05_master_sector.ent.json").write_text(json.dumps(ep05_sec_doc, indent=2), encoding="utf-8")

    # 20. chispa_ep05_containment_pylon.ent.json (Ep. 5 NetWatch containment stand + yellow relay)
    p501 = copy.deepcopy(base_comps[0])
    p501["id"] = "9300000000000000191"
    p501["name"]["$value"] = "ch_ep05_pylon_stand"
    _set_mesh(p501, MESH_COMPUTER_STAND, "default")
    _set_scale(p501, 0.80, 0.80, 0.80)
    _set_fixed_pos(p501, 0, 0, 0)

    p502 = copy.deepcopy(base_comps[0])
    p502["id"] = "9300000000000000192"
    p502["name"]["$value"] = "ch_ep05_pylon_relay"
    _set_mesh(p502, MESH_ELEC_BOX_H, "yellow")
    _set_scale(p502, 0.95, 0.95, 0.95)
    _set_fixed_pos(p502, 48000, 0, 0)

    p503 = copy.deepcopy(base_comps[2])
    _set_light(p503, "ch_ep05_pylon_blue", "9300000000000000193", 40, 175, 255, 155, 4.5, 195000)

    p504 = copy.deepcopy(base_comps[3])
    _set_light(p504, "ch_ep05_pylon_amber", "9300000000000000194", 255, 180, 40, 115, 3.5, 135000)

    ep05_pylon_doc = _sync_redpackage_and_deps(
        copy.deepcopy(case_tmpl),
        "chispa_nc\\entities\\chispa_ep05_containment_pylon.ent",
        [p501, p502, p503, p504],
        [MESH_COMPUTER_STAND, MESH_ELEC_BOX_H],
    )
    (OUT_ENT_DIR / "chispa_ep05_containment_pylon.ent.json").write_text(json.dumps(ep05_pylon_doc, indent=2), encoding="utf-8")

    print(f"[OK] Entities generated in {OUT_ENT_DIR}")


if __name__ == "__main__":
    build_entities()
