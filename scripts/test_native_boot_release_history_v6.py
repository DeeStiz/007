#!/usr/bin/env python3
"""Fail-closed Release provenance and source-catalog generation gate.

This gate is intentionally additive to the main Release build/launch scripts.
It pins the final source-scene root and every preserved GEFV/GESM generation,
then rechecks the frozen V1--V5 evidence and application boundary.  It never
opens the ROM for runtime use; the ROM is hashed only as preparation evidence.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import struct
import subprocess
import sys


PROJECT_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_PATH = PROJECT_ROOT / "scripts/fixtures/native-boot-source-v6-history.fixture"
SOURCE_SCRIPT = PROJECT_ROOT / "scripts/prepare_native_source_frontend_v6.py"
R0_SCRIPT = PROJECT_ROOT / "scripts/test_fidelity_recovery_r0.sh"
R0_LOCK_PATH = Path("/tmp/goldeneye-native-r0-v5.lock")
SOURCE_RELATIVE = Path("build/native/source-frontend-v6")
MODELS = (
    "chrwppk",
    "goldeneyelogo",
    "headbrosnansuit",
    "legalpage",
    "nintendologo",
    "rarewarelogo",
    "suitbond",
    "walletbond",
)
HISTORY_KEYS = ("packet_sha256", "packet_file_sha256", "sums_file_sha256", "record_count", "sidecar_count")
SIDECAR_COUNTS = ("nodes", "display_lists", "commands", "vertices", "textures", "mips", "tluts", "raw_gfx")
V5_HEADERS = {
    "ge_audio_engine": "native/include/ge_audio_engine_v5.h",
    "ge_audio_output": "native/include/ge_audio_output_v5.h",
    "ge_audio_source_node": "native/include/ge_audio_source_node_v5.h",
    "ge_audio": "native/include/ge_audio_v5.h",
    "ge_classic_raster": "native/include/ge_classic_raster_v5.h",
    "ge_native_runtime": "native/include/ge_native_runtime_v5.h",
    "ge_ramrom_playback": "native/include/ge_ramrom_playback_v5.h",
    "ge_ramrom": "native/include/ge_ramrom_v5.h",
    "ge_stage": "native/include/ge_stage_v5.h",
    "ge_title_raster": "native/include/ge_title_raster_v5.h",
    "ge_title_route": "native/include/ge_title_route_v5.h",
    "ge_native_foundation": "native/include/ge_native_foundation.h",
}
FROZEN_LOG_V1_V3 = PROJECT_ROOT / "build/native/classic-textures/texture-replay-smoke.log"
FROZEN_LOG_V4 = PROJECT_ROOT / "build/native/classic-combiner/classic-combiner-run-a.log"


class GateFailure(RuntimeError):
    pass


def fail(message: str) -> "NoReturn":
    raise GateFailure(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha1(path: Path) -> str:
    digest = hashlib.sha1()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_file(path: Path, description: str | None = None) -> Path:
    if not path.is_file() or path.stat().st_size == 0:
        fail(f"missing or empty {description or 'file'}: {path}")
    return path


def require_directory(path: Path, description: str) -> Path:
    if not path.is_dir():
        fail(f"missing {description}: {path}")
    return path


def run(command: list[str], *, cwd: Path = PROJECT_ROOT, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True, check=False)
    except OSError as error:
        fail(f"could not execute {shlex.join(command)}: {error}")


def parse_fixture(path: Path) -> dict[str, str]:
    require_file(path, "Release history fixture")
    values: dict[str, str] = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            fail(f"malformed fixture line {line_number}: {raw}")
        key, value = line.split("=", 1)
        if not key or key in values:
            fail(f"duplicate or empty fixture key on line {line_number}: {key}")
        values[key] = value
    return values


def int_fixture(values: dict[str, str], key: str) -> int:
    try:
        return int(values[key], 10)
    except (KeyError, ValueError):
        fail(f"invalid integer fixture value: {key}")


def expect(values: dict[str, str], key: str) -> str:
    value = values.get(key)
    if value is None or value == "":
        fail(f"fixture is missing {key}")
    return value


def require_under(path: Path, root: Path, description: str) -> Path:
    try:
        path.relative_to(root)
    except ValueError:
        fail(f"{description} escapes its allowed root: {path}")
    return path


def parse_kv_text(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        values[key] = value
    return values


def check_rom_and_reference(values: dict[str, str], rom_input: Path) -> Path:
    rom = rom_input.expanduser().resolve()
    require_file(rom, "external preparation ROM")
    require_under(PROJECT_ROOT, PROJECT_ROOT.parent, "project root")
    try:
        rom.relative_to(PROJECT_ROOT)
    except ValueError:
        pass
    else:
        fail(f"external ROM is inside the checkout: {rom}")
    expected_size = int_fixture(values, "rom_size")
    if rom.stat().st_size != expected_size:
        fail(f"external ROM size mismatch: expected {expected_size}, got {rom.stat().st_size}")
    expected_sha1 = expect(values, "rom_sha1")
    actual_sha1 = sha1(rom)
    if actual_sha1 != expected_sha1:
        fail(f"external ROM SHA-1 mismatch: expected {expected_sha1}, got {actual_sha1}")

    evidence = require_file(PROJECT_ROOT / ".porting/m0-provenance.md", "Linux reference evidence")
    evidence_text = evidence.read_text(encoding="utf-8")
    for key in ("reference_command", "reference_hash_command", "rom_sha1"):
        if expect(values, key) not in evidence_text:
            fail(f"reference evidence is missing {key}")
    return rom


def check_git_boundary() -> None:
    for pattern in ("*.z64", "*.n64", "*.Z64", "*.N64"):
        result = run(["git", "ls-files", "--", pattern])
        if result.returncode != 0:
            fail(f"git ls-files failed for {pattern}: {result.stderr.strip()}")
        if result.stdout.strip():
            fail(f"a ROM is tracked by the checkout: {result.stdout.strip()}")
    private_paths = (
        "assets/obseg/prop/Pammo_crate1Z.bin",
        "assets/images/split/AMMOCRATE1.bin",
        "assets/images/split/AMMOTEXT765.bin",
        "assets/images/split/CRATEROPE.bin",
    )
    result = run(["git", "ls-files", "--", *private_paths])
    if result.returncode != 0:
        fail(f"git ls-files failed for private payload guard: {result.stderr.strip()}")
    if result.stdout.strip():
        fail(f"a private extracted payload is tracked by the checkout: {result.stdout.strip()}")

    runtime_pattern = re.compile(r"(?:goldeneye[^\s\"'`]*|[^\s\"'`]+)\.(?:z64|n64)\b", re.IGNORECASE)
    for directory in (PROJECT_ROOT / "native/host", PROJECT_ROOT / "native/src"):
        for path in directory.rglob("*"):
            if path.suffix.lower() not in {".swift", ".c", ".m", ".mm"}:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            if runtime_pattern.search(text):
                fail(f"runtime source contains a ROM-file literal: {path}")


def check_frozen_contracts(values: dict[str, str], rom: Path) -> None:
    # Re-run the existing R0 guard so its C layout probe remains the authority
    # for the complete V5 record set.  This lane adds the exact value checks
    # below, rather than duplicating its compiler probe.
    environment = os.environ.copy()
    environment["GOLDENEYE_US_ROM"] = str(rom)
    # The existing R0 guard writes a shared ignored layout snapshot.  Serialize
    # this additive gate's R0 invocation so two release checks cannot race on
    # that evidence file.
    with R0_LOCK_PATH.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        result = run([str(R0_SCRIPT)], env=environment)
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
    if result.returncode != 0 or "[R0] PASS" not in (result.stdout + result.stderr):
        tail = (result.stdout + result.stderr).strip().splitlines()[-12:]
        fail(f"frozen R0/V5 guard failed: {' | '.join(tail)}")

    v1_v3 = require_file(FROZEN_LOG_V1_V3, "V1-V3 replay evidence").read_text(encoding="utf-8")
    v4 = require_file(FROZEN_LOG_V4, "V4 combiner evidence").read_text(encoding="utf-8")
    v1_v2_line = (
        f"V1/V2 regression hashes: PASS v1={expect(values, 'v1')} "
        f"v2Packet={expect(values, 'v2_packet')} v2Event={expect(values, 'v2_event')} "
        f"v2State={expect(values, 'v2_state')}"
    )
    v3_line = (
        "textured replay: PASS path=/Users/derek/Developer/goldeneye-swift/build/native/classic-prop/Pammo_crate1Z.bin "
        "commands=24 draws=4 vertices=40 triangles=20 "
        f"packetHash={expect(values, 'v3_packet')} eventHash={expect(values, 'v3_event')} "
        f"materialHash={expect(values, 'v3_material')}"
    )
    v4_line = (
        "classic combiner: PASS commands=22 setup=3 draws=4 "
        f"setupHash={expect(values, 'v4_setup')} eventHash={expect(values, 'v4_event')} keyHash={expect(values, 'v4_key')}"
    )
    for line, content, label in ((v1_v2_line, v1_v3, "V1/V2"), (v3_line, v1_v3, "V3"), (v4_line, v4, "V4")):
        if line not in content:
            fail(f"frozen {label} evidence changed")

    for key, relative in V5_HEADERS.items():
        path = require_file(PROJECT_ROOT / relative, f"V5 header {relative}")
        digest = sha256(path)
        if digest != expect(values, f"v5_header_{key}"):
            fail(f"V5 header hash changed: {relative} ({digest})")
    evidence_root = PROJECT_ROOT / "build/native/fidelity-recovery"
    for name, key in (("v5-layout.txt", "v5_layout_sha256"), ("v5-public-header-sha256.txt", "v5_header_manifest_sha256")):
        path = require_file(evidence_root / name, f"R0 {name}")
        digest = sha256(path)
        if digest != expect(values, key):
            fail(f"R0 {name} hash changed: {digest}")


def verify_prepared_root(values: dict[str, str], source_root: Path) -> None:
    source_root = source_root.expanduser().resolve()
    require_directory(source_root, "prepared source frontend root")
    build_root = (PROJECT_ROOT / "build/native").resolve()
    require_under(source_root, build_root, "prepared source frontend root")
    ignored = run(["git", "check-ignore", "-q", str(source_root)])
    if ignored.returncode != 0:
        fail(f"prepared source frontend root is not ignored: {source_root}")

    packet = require_file(source_root / "source-frontend-v6.gefv", "final GEFV packet")
    manifest_json_path = require_file(source_root / "source-frontend-v6-manifest.json", "final GEFV JSON manifest")
    manifest_txt_path = require_file(source_root / "source-frontend-v6-manifest.txt", "final GEFV text manifest")
    report_path = require_file(source_root / "source-frontend-v6-report.txt", "final GEFV report")
    manifest = json.loads(manifest_json_path.read_text(encoding="utf-8"))
    text_manifest = parse_kv_text(manifest_txt_path)
    text_sidecars: dict[str, dict[str, str]] = {}
    for raw in manifest_txt_path.read_text(encoding="utf-8").splitlines():
        if not raw.startswith("sidecar_") or raw.startswith("sidecar_count=") or "=" not in raw:
            continue
        key, encoded = raw.split("=", 1)
        row: dict[str, str] = {}
        for field in encoded.split(","):
            if ":" in field:
                field_key, field_value = field.split(":", 1)
                row[field_key] = field_value
        text_sidecars[key[len("sidecar_"):]] = row
    expected_flags = {
        "manifest_version": "6",
        "magic": "GEFV",
        "goal": expect(values, "goal"),
        "status": "PASS",
        "runtime_rom_access": "false",
        "external_rom_sha1": expect(values, "rom_sha1"),
        "rom_copied_into_checkout": "false",
        "rom_copied_into_bundle": "false",
        "private_payloads_copied_into_checkout": "false",
        "private_payloads_copied_into_bundle": "false",
    }
    for key, expected in expected_flags.items():
        if text_manifest.get(key) != expected:
            fail(f"final GEFV manifest {key} mismatch: {text_manifest.get(key)!r}")
    provenance = manifest.get("provenance", {})
    for key in ("rom_copied_into_checkout", "rom_copied_into_bundle", "private_payloads_copied_into_checkout", "private_payloads_copied_into_bundle"):
        if provenance.get(key) is not False:
            fail(f"final GEFV provenance flag is not false: {key}")
    if manifest.get("manifest_version") != 6 or manifest.get("magic") != "GEFV" or manifest.get("goal") != expect(values, "goal"):
        fail("final GEFV JSON identity mismatch")
    if manifest.get("runtime_rom_access") is not False or manifest.get("external_rom_sha1") != expect(values, "rom_sha1"):
        fail("final GEFV JSON runtime/provenance boundary mismatch")

    scalar_expectations = {
        "packet_sha256": expect(values, "final_packet_sha256"),
        "packet_bytes": int_fixture(values, "final_packet_bytes"),
        "payload_bytes": int_fixture(values, "final_payload_bytes"),
        "source_catalog_sha256": expect(values, "final_source_catalog_sha256"),
    }
    for key, expected in scalar_expectations.items():
        if manifest.get(key) != expected:
            fail(f"final GEFV {key} mismatch: {manifest.get(key)!r}")
    if len(manifest.get("records", [])) != int_fixture(values, "final_record_count"):
        fail("final GEFV record count mismatch")
    if len(manifest.get("sidecars", [])) != int_fixture(values, "final_sidecar_count"):
        fail("final GEFV sidecar count mismatch")
    if sha256(packet) != expect(values, "final_packet_file_sha256"):
        fail("final GEFV file hash mismatch")

    count_map = {
        "texture_payload": "final_count_texture_payload",
        "mip_payload": "final_count_mip_payload",
        "tlut_payload": "final_count_tlut_payload",
        "model": "final_count_model",
        "node": "final_count_node",
        "display_list": "final_count_display_list",
        "vertex_group": "final_count_vertex_group",
    }
    counts = manifest.get("counts", {})
    for category, fixture_key in count_map.items():
        if counts.get(category) != int_fixture(values, fixture_key):
            fail(f"final GEFV category count mismatch: {category}")
    for required in ("status=PASS", "runtime_rom_access=false", "record_count=" + expect(values, "final_record_count")):
        if required not in report_path.read_text(encoding="utf-8"):
            fail(f"final GEFV report is missing {required}")

    verifier = [sys.executable, str(SOURCE_SCRIPT), "--verify", str(packet)]
    result = run(verifier)
    if result.returncode != 0:
        fail(f"final GEFV verifier failed: {result.stderr.strip()}")

    rows = {row.get("name"): row for row in manifest.get("sidecars", [])}
    if set(rows) != set(MODELS):
        fail("final GEFV sidecar inventory mismatch")
    for model in MODELS:
        row = rows[model]
        text_row = text_sidecars.get(model, {})
        prefix = f"final_sidecar_{model}_"
        expected_packet = expect(values, prefix + "packet_sha256")
        if row.get("packet_sha256") != expected_packet:
            fail(f"final GESM canonical hash mismatch: {model}")
        if row.get("unsupported_macros") not in ([], None):
            fail(f"final GESM has unsupported macros: {model}")
        relative = row.get("path", "")
        sidecar = (source_root / relative).resolve()
        require_under(sidecar, source_root, f"GESM sidecar {model}")
        require_file(sidecar, f"final GESM sidecar {model}")
        if sha256(sidecar) != expect(values, prefix + "file_sha256"):
            fail(f"final GESM file hash mismatch: {model}")
        if row.get("bytes") != sidecar.stat().st_size:
            fail(f"final GESM byte count mismatch: {model}")
        for count_key in SIDECAR_COUNTS:
            actual_count = row.get(count_key, text_row.get(count_key, 0))
            if int(actual_count) != int_fixture(values, prefix + count_key):
                fail(f"final GESM {count_key} mismatch: {model}")
        audit = row.get("handle_audit", {})
        for resource in ("display_list", "texture", "vertex_group"):
            resource_audit = audit.get(resource, {})
            if resource_audit.get("declared") != resource_audit.get("referenced") or resource_audit.get("unused") != 0:
                fail(f"final GESM handle audit mismatch: {model}/{resource}")
        sidecar_result = run([sys.executable, str(SOURCE_SCRIPT), "--verify-sidecar", str(sidecar)])
        if sidecar_result.returncode != 0:
            fail(f"final GESM verifier failed: {model}: {sidecar_result.stderr.strip()}")

    selectfile = next((row for row in manifest.get("records", []) if row.get("name") == "SELECTFILE.payload" and row.get("category") == "texture_payload"), None)
    if selectfile is None:
        fail("final GEFV SELECTFILE payload is missing")
    if selectfile.get("decoded_sha256") != expect(values, "final_selectfile_decoded_sha256") or selectfile.get("decoded_size") != int_fixture(values, "final_selectfile_decoded_size"):
        fail("final GEFV SELECTFILE payload metadata mismatch")
    header = struct.Struct("<4sIIIIII32s32sI")
    packet_bytes = packet.read_bytes()
    if len(packet_bytes) < header.size:
        fail("final GEFV packet is truncated")
    _, _, _, manifest_bytes, _, _, _, _, _, _ = header.unpack_from(packet_bytes)
    payload_base = header.size + manifest_bytes
    offset = int(selectfile.get("decoded_payload_offset", -1))
    size = int(selectfile.get("decoded_size", 0))
    payload = packet_bytes[payload_base + offset:payload_base + offset + size]
    if offset < 0 or size <= 0 or len(payload) != size or not any(payload):
        fail("final GEFV SELECTFILE decoded payload is empty or out of bounds")
    if hashlib.sha256(payload).hexdigest() != expect(values, "final_selectfile_decoded_sha256"):
        fail("final GEFV SELECTFILE decoded payload hash mismatch")

    for path in source_root.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".z64", ".n64", ".rom"}:
            fail(f"ROM-like payload found in prepared source root: {path}")


def verify_history(values: dict[str, str], source_root: Path) -> list[str]:
    history_root = source_root / "history"
    require_directory(history_root, "GEFV/GESM history root")
    history_count = int_fixture(values, "history_count")
    expected_roots = [expect(values, f"history_{index}_root") for index in range(1, history_count + 1)]
    actual_roots = sorted(str(path.relative_to(source_root)) for path in history_root.iterdir() if path.is_dir())
    if sorted(expected_roots) != actual_roots:
        fail(f"GEFV/GESM history inventory mismatch: expected {sorted(expected_roots)}, got {actual_roots}")

    verified: list[str] = []
    for index, relative in enumerate(expected_roots, 1):
        root = (source_root / relative).resolve()
        require_under(root, source_root, "GEFV/GESM history generation")
        generation = root.name
        if generation != expect(values, f"history_{index}_packet_sha256"):
            fail(f"history directory/hash mismatch: {relative}")
        manifest_path = require_file(root / "source-frontend-v6-manifest.txt", f"history {generation} manifest")
        report_path = require_file(root / "source-frontend-v6-report.txt", f"history {generation} report")
        json_path = require_file(root / "source-frontend-v6-manifest.json", f"history {generation} JSON manifest")
        packet_path = require_file(root / "source-frontend-v6.gefv", f"history {generation} GEFV packet")
        sums_path = require_file(root / "SHA256SUMS", f"history {generation} SHA256SUMS")
        manifest = parse_kv_text(manifest_path)
        expected_packet = expect(values, f"history_{index}_packet_sha256")
        if manifest.get("packet_sha256") != expected_packet or manifest.get("record_count") != expect(values, f"history_{index}_record_count") or manifest.get("sidecar_count") != expect(values, f"history_{index}_sidecar_count"):
            fail(f"history {generation} manifest identity/count mismatch")
        if f"packet_sha256={expected_packet}" not in report_path.read_text(encoding="utf-8"):
            fail(f"history {generation} report hash mismatch")
        if sha256(packet_path) != expect(values, f"history_{index}_packet_file_sha256"):
            fail(f"history {generation} GEFV file hash mismatch")
        if sha256(sums_path) != expect(values, f"history_{index}_sums_file_sha256"):
            fail(f"history {generation} SHA256SUMS file changed")
        json_manifest = json.loads(json_path.read_text(encoding="utf-8"))
        if json_manifest.get("packet_sha256") != expected_packet or len(json_manifest.get("records", [])) != int_fixture(values, f"history_{index}_record_count"):
            fail(f"history {generation} JSON manifest mismatch")
        for model in MODELS:
            require_file(root / f"{model}.gesm", f"history {generation} {model}.gesm")
        sums_result = run(["shasum", "-a", "256", "-c", str(sums_path)])
        if sums_result.returncode != 0:
            fail(f"history {generation} SHA256SUMS verification failed: {sums_result.stdout.strip()} {sums_result.stderr.strip()}")
        verified.append(generation)
    return verified


def verify_bundle(bundle_input: Path) -> None:
    bundle = bundle_input.expanduser().resolve()
    require_directory(bundle, "source-faithful application bundle")
    resource_root = bundle / "Contents/Resources"
    require_directory(resource_root, "application Resources directory")
    require_file(bundle / "Contents/MacOS/GoldenEyeHost", "application executable")
    require_file(bundle / "Contents/Info.plist", "application Info.plist")
    resource_files = [path for path in resource_root.rglob("*") if path.is_file()]
    forbidden_suffixes = {
        ".z64", ".n64", ".rom", ".gefv", ".gesm", ".gepk", ".getx", ".bin", ".rz", ".ctl", ".tbl",
        ".seq", ".aifc", ".aiff", ".sbk", ".decoded", ".raw", ".air", ".metal",
    }
    forbidden_names = {"goldeneyetitle.metallib", "goldeneyestagebackground.metallib"}
    allowed_shader_prefixes = ("GoldenEyeSource", "GoldenEyeClassic", "GoldenEyeStageScene")
    for path in resource_files:
        name = path.name
        lower = name.lower()
        if path.suffix.lower() in forbidden_suffixes:
            fail(f"private/procedural resource in source-faithful bundle: {path.relative_to(bundle)}")
        if lower in forbidden_names or "diagnostic" in lower or "procedural" in lower:
            fail(f"diagnostic/procedural resource in source-faithful bundle: {path.relative_to(bundle)}")
        if path.suffix.lower() == ".metallib" and not name.startswith(allowed_shader_prefixes):
            fail(f"unapproved Metal library in source-faithful bundle: {path.relative_to(bundle)}")
    if not any(path.name == "GoldenEyeSourceSceneV6.metallib" for path in resource_files):
        fail("source-faithful bundle is missing GoldenEyeSourceSceneV6.metallib")

    binary_patterns = (
        b"GoldenEye 007 (USA).z64",
    )
    for path in [p for p in bundle.rglob("*") if p.is_file()]:
        data = path.read_bytes()
        for pattern in binary_patterns:
            if pattern in data:
                fail(f"private ROM/catalog path embedded in bundle: {path.relative_to(bundle)} ({pattern.decode(errors='replace')})")

    codesign = run(["codesign", "-dv", "--verbose=4", str(bundle)])
    signature = codesign.stdout + codesign.stderr
    if codesign.returncode != 0 or not re.search(r"^Authority=", signature, re.MULTILINE):
        fail("source-faithful application is not signed by a certificate authority")
    if re.search(r"Signature=adhoc|Authority=adhoc", signature, re.IGNORECASE):
        fail("ad-hoc application signature is forbidden")
    verified = run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(bundle)])
    if verified.returncode != 0:
        fail(f"application code signature verification failed: {verified.stderr.strip()}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom", nargs="?", help="external verified ROM used only for provenance hashing")
    parser.add_argument("--bundle", help="optional signed source-faithful .app to inspect")
    parser.add_argument("--source-root", default=os.environ.get("GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT", str(PROJECT_ROOT / SOURCE_RELATIVE)))
    args = parser.parse_args()
    values = parse_fixture(FIXTURE_PATH)
    if expect(values, "fixture_version") != "1" or expect(values, "goal") != "native-boot-menu-attract-120":
        fail("Release history fixture identity mismatch")
    rom_default = os.environ.get("GOLDENEYE_US_ROM", "/Users/derek/Documents/GoldenEye 007 (USA).z64")
    rom = check_rom_and_reference(values, Path(args.rom or rom_default))
    check_git_boundary()
    check_frozen_contracts(values, rom)
    source_root = Path(args.source_root)
    verify_prepared_root(values, source_root)
    verified_history = verify_history(values, source_root)
    if args.bundle:
        verify_bundle(Path(args.bundle))
    print("native boot Release history/provenance gate: PASS")
    print(f"external_rom_sha1={sha1(rom)}")
    print(f"final_packet_sha256={expect(values, 'final_packet_sha256')}")
    print(f"history_generations={','.join(verified_history)}")
    print(f"v1_v5_frozen=true")
    print(f"bundle_checked={args.bundle is not None}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GateFailure as error:
        print(f"native boot Release history/provenance gate: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
