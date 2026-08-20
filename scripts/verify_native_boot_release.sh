#!/bin/bash
set -euo pipefail

# Release-only provenance and packaging gate for the source-faithful native
# boot product.  This gate is deliberately independent of the Swift owner and
# renderer: it validates the external input boundary, the prepared V6 catalog,
# and the final application envelope before a launch is allowed.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

ROM_SHA1_EXPECTED="abe01e4aeb033b6c0836819f549c791b26cfde83"
ROM_SIZE_EXPECTED=12582912
REFERENCE_EVIDENCE_PATH="${PROJECT_ROOT}/.porting/m0-provenance.md"
REFERENCE_COMMAND='make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1'
REFERENCE_HASH_COMMAND='sha1sum -c ge007.u.sha1'
SOURCE_FRONTEND_V6_SCRIPT="${SCRIPT_DIR}/prepare_native_source_frontend_v6.py"
EXPECTED_FIXTURE="${SCRIPT_DIR}/fixtures/native-boot-source-v6-image-decoder-v6-final.fixture"
EXPECTED_FIXTURE_SHA256="7e08adc6de0836293fcc6a33dac15d4076f4c6ec424cd6f6b22fa94017df8b79"
SOURCE_FRONTEND_RELATIVE="build/native/source-frontend-v6-image-decoder-v6"

BOOT_ASSET_ROOT="${GOLDENEYE_NATIVE_BOOT_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets}"
STAGE_ASSET_ROOT="${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}"
SOURCE_FRONTEND_ROOT="${GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT:-${PROJECT_ROOT}/${SOURCE_FRONTEND_RELATIVE}}"

MODE="prepared"
DRY_RUN=0
APP_PATH=""

usage() {
    cat >&2 <<'USAGE'
Usage:
  verify_native_boot_release.sh [--dry-run] [--bundle APP] /absolute/path/to/GoldenEye-007-US.z64

The default mode validates prepared assets.  --bundle additionally validates
that APP contains only the source-scene and source-2D metallibs and has a
non-ad-hoc code signature.  --dry-run performs the same read-only checks and
prints the package/launch plan without modifying the checkout or build output.
USAGE
    exit 2
}

fail() {
    printf 'native boot release gate: FAIL: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "required file is missing: $1"
}

require_nonempty_file() {
    require_file "$1"
    [[ -s "$1" ]] || fail "required file is empty: $1"
}

require_line() {
    local expected="$1"
    local path="$2"
    grep -Fqx "${expected}" "${path}" ||
        fail "required manifest line is missing or changed in ${path}: ${expected}"
}

sha1() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 1 "$1" | awk '{print $1}'
    elif command -v sha1sum >/dev/null 2>&1; then
        sha1sum "$1" | awk '{print $1}'
    else
        fail "neither shasum nor sha1sum is available"
    fi
}

sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        fail "neither shasum nor sha256sum is available"
    fi
}

byte_count() {
    wc -c < "$1" | tr -d '[:space:]'
}

realpath_for() {
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

inside_root() {
    local candidate="$1"
    local root="$2"
    case "${candidate}" in
        "${root}"|"${root}"/*) return 0 ;;
        *) return 1 ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --bundle)
            [[ $# -ge 2 ]] || usage
            MODE="bundle"
            APP_PATH="$2"
            shift 2
            ;;
        --prepared)
            MODE="prepared"
            shift
            ;;
        --help|-h)
            usage
            ;;
        --*)
            usage
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -eq 1 ]] || usage
ROM_PATH_INPUT="$1"

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v git >/dev/null 2>&1 || fail "git is required for ignored-output guards"
require_file "${ROM_PATH_INPUT}"
require_file "${REFERENCE_EVIDENCE_PATH}"
require_file "${SOURCE_FRONTEND_V6_SCRIPT}"
require_nonempty_file "${EXPECTED_FIXTURE}"

fixture_sha256=$(sha256 "${EXPECTED_FIXTURE}")
[[ "${fixture_sha256}" == "${EXPECTED_FIXTURE_SHA256}" ]] ||
    fail "release expectation fixture hash mismatch: ${EXPECTED_FIXTURE}"

fixture_value() {
    local key="$1"
    awk -F= -v key="${key}" '$1 == key { print substr($0, length($1) + 2); found = 1 } END { if (!found) exit 1 }' \
        "${EXPECTED_FIXTURE}"
}

EXPECTED_PACKET_SHA256=$(fixture_value packet_sha256) ||
    fail "release expectation fixture is missing packet_sha256"
EXPECTED_PACKET_FILE_SHA256=$(fixture_value packet_file_sha256) ||
    fail "release expectation fixture is missing packet_file_sha256"
EXPECTED_PACKET_BYTES=$(fixture_value packet_bytes) ||
    fail "release expectation fixture is missing packet_bytes"
EXPECTED_PAYLOAD_BYTES=$(fixture_value payload_bytes) ||
    fail "release expectation fixture is missing payload_bytes"
EXPECTED_SOURCE_CATALOG_SHA256=$(fixture_value source_catalog_sha256) ||
    fail "release expectation fixture is missing source_catalog_sha256"
EXPECTED_SOURCE_FRONTEND_RELATIVE=$(fixture_value source_root) ||
    fail "release expectation fixture is missing source_root"
PRESERVED_LEGACY_SOURCE_ROOT_RELATIVE=$(fixture_value preserved_legacy_source_root) ||
    fail "release expectation fixture is missing preserved_legacy_source_root"
PRESERVED_LEGACY_PACKET_SHA256=$(fixture_value preserved_legacy_packet_sha256) ||
    fail "release expectation fixture is missing preserved_legacy_packet_sha256"
PRESERVED_LEGACY_PACKET_FILE_SHA256=$(fixture_value preserved_legacy_packet_file_sha256) ||
    fail "release expectation fixture is missing preserved_legacy_packet_file_sha256"
EXPECTED_RECORD_COUNT=$(fixture_value record_count) ||
    fail "release expectation fixture is missing record_count"
EXPECTED_TEXTURE_PAYLOAD_COUNT=$(fixture_value count_texture_payload) ||
    fail "release expectation fixture is missing count_texture_payload"
EXPECTED_MIP_PAYLOAD_COUNT=$(fixture_value count_mip_payload) ||
    fail "release expectation fixture is missing count_mip_payload"
EXPECTED_TLUT_PAYLOAD_COUNT=$(fixture_value count_tlut_payload) ||
    fail "release expectation fixture is missing count_tlut_payload"
EXPECTED_MODEL_COUNT=$(fixture_value count_model) ||
    fail "release expectation fixture is missing count_model"
EXPECTED_NODE_COUNT=$(fixture_value count_node) ||
    fail "release expectation fixture is missing count_node"
EXPECTED_DISPLAY_LIST_COUNT=$(fixture_value count_display_list) ||
    fail "release expectation fixture is missing count_display_list"
EXPECTED_VERTEX_GROUP_COUNT=$(fixture_value count_vertex_group) ||
    fail "release expectation fixture is missing count_vertex_group"
EXPECTED_SIDECAR_COUNT=$(fixture_value sidecar_count) ||
    fail "release expectation fixture is missing sidecar_count"
EXPECTED_HISTORICAL_PACKET_SHA256=$(fixture_value historical_packet_sha256) ||
    fail "release expectation fixture is missing historical_packet_sha256"
HISTORICAL_SOURCE_ROOT_RELATIVE=$(fixture_value historical_source_root) ||
    fail "release expectation fixture is missing historical_source_root"
HISTORICAL_RELATIVE_ROOT=$(fixture_value historical_root) ||
    fail "release expectation fixture is missing historical_root"
HISTORICAL_RELATIVE_SUMS=$(fixture_value historical_sums) ||
    fail "release expectation fixture is missing historical_sums"
EXPECTED_SELECTFILE_PAYLOAD=$(fixture_value selectfile_payload) ||
    fail "release expectation fixture is missing selectfile_payload"
EXPECTED_SELECTFILE_DECODED_SHA256=$(fixture_value selectfile_decoded_sha256) ||
    fail "release expectation fixture is missing selectfile_decoded_sha256"
EXPECTED_SELECTFILE_DECODED_SIZE=$(fixture_value selectfile_decoded_size) ||
    fail "release expectation fixture is missing selectfile_decoded_size"

[[ "${EXPECTED_SOURCE_FRONTEND_RELATIVE}" == "${SOURCE_FRONTEND_RELATIVE}" ]] ||
    fail "release fixture source_root is not the versioned corrected catalog: ${EXPECTED_SOURCE_FRONTEND_RELATIVE}"
EXPECTED_SOURCE_FRONTEND_REAL_PATH=$(realpath_for "${PROJECT_ROOT}/${EXPECTED_SOURCE_FRONTEND_RELATIVE}")
SOURCE_FRONTEND_REAL_PATH=$(realpath_for "${SOURCE_FRONTEND_ROOT}")
[[ "${SOURCE_FRONTEND_REAL_PATH}" == "${EXPECTED_SOURCE_FRONTEND_REAL_PATH}" ]] ||
    fail "Release must use the versioned corrected source catalog: expected ${EXPECTED_SOURCE_FRONTEND_REAL_PATH}, got ${SOURCE_FRONTEND_REAL_PATH}"
PRESERVED_LEGACY_SOURCE_ROOT="${PROJECT_ROOT}/${PRESERVED_LEGACY_SOURCE_ROOT_RELATIVE}"
inside_root "$(realpath_for "${PRESERVED_LEGACY_SOURCE_ROOT}")" "${PROJECT_ROOT}/build/native" ||
    fail "preserved legacy source catalog escapes build/native: ${PRESERVED_LEGACY_SOURCE_ROOT}"
PRESERVED_LEGACY_PACKET="${PRESERVED_LEGACY_SOURCE_ROOT}/source-frontend-v6.gefv"
if [[ -e "${PRESERVED_LEGACY_SOURCE_ROOT}" || -e "${PRESERVED_LEGACY_PACKET}" ]]; then
    require_nonempty_file "${PRESERVED_LEGACY_PACKET}"
    [[ "$(sha256 "${PRESERVED_LEGACY_PACKET}")" == "${PRESERVED_LEGACY_PACKET_FILE_SHA256}" ]] ||
        fail "preserved b924 GEFV packet file changed"
    python3 "${SOURCE_FRONTEND_V6_SCRIPT}" --verify "${PRESERVED_LEGACY_PACKET}" 2>/dev/null |
        grep -Fqx "packet_sha256=${PRESERVED_LEGACY_PACKET_SHA256}" ||
        fail "preserved b924 GEFV packet hash changed"
fi

ROM_DIR=$(cd -- "$(dirname -- "${ROM_PATH_INPUT}")" && pwd -P) ||
    fail "unable to resolve external ROM directory"
ROM_PATH="${ROM_DIR}/$(basename -- "${ROM_PATH_INPUT}")"
ROM_REAL_PATH=$(realpath_for "${ROM_PATH}")
if inside_root "${ROM_REAL_PATH}" "${PROJECT_ROOT}"; then
    fail "the ROM must remain outside the checkout: ${ROM_REAL_PATH}"
fi

grep -Fq "${REFERENCE_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "the canonical Linux reference command is missing from ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${REFERENCE_HASH_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "the canonical Linux reference hash command is missing from ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${ROM_SHA1_EXPECTED}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "the canonical ROM SHA-1 is missing from ${REFERENCE_EVIDENCE_PATH}"

rom_size=$(byte_count "${ROM_REAL_PATH}")
[[ "${rom_size}" == "${ROM_SIZE_EXPECTED}" ]] ||
    fail "external ROM size mismatch: expected ${ROM_SIZE_EXPECTED}, got ${rom_size}"
rom_sha1=$(sha1 "${ROM_REAL_PATH}")
[[ "${rom_sha1}" == "${ROM_SHA1_EXPECTED}" ]] ||
    fail "external ROM SHA-1 mismatch: expected ${ROM_SHA1_EXPECTED}, got ${rom_sha1}"

tracked_roms=$(git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64' '*.Z64' '*.N64')
[[ -z "${tracked_roms}" ]] || fail "a ROM is tracked by the checkout: ${tracked_roms}"

for output_root in "${BOOT_ASSET_ROOT}" "${STAGE_ASSET_ROOT}" "${SOURCE_FRONTEND_ROOT}"; do
    output_real_path=$(realpath_for "${output_root}")
    inside_root "${output_real_path}" "${PROJECT_ROOT}/build/native" ||
        fail "private prepared output is outside build/native: ${output_real_path}"
    git -C "${PROJECT_ROOT}" check-ignore -q "${output_root}" ||
        fail "private prepared output is not ignored: ${output_root}"
done

BOOT_MANIFEST="${BOOT_ASSET_ROOT}/native-boot-assets-manifest.txt"
STAGE_MANIFEST="${STAGE_ASSET_ROOT}/stage-assets-manifest.txt"
SOURCE_REPORT="${SOURCE_FRONTEND_ROOT}/source-frontend-v6-report.txt"
SOURCE_MANIFEST="${SOURCE_FRONTEND_ROOT}/source-frontend-v6-manifest.txt"
SOURCE_JSON="${SOURCE_FRONTEND_ROOT}/source-frontend-v6-manifest.json"
SOURCE_PACKET="${SOURCE_FRONTEND_ROOT}/source-frontend-v6.gefv"

require_nonempty_file "${BOOT_MANIFEST}"
require_nonempty_file "${STAGE_MANIFEST}"
require_nonempty_file "${SOURCE_REPORT}"
require_nonempty_file "${SOURCE_MANIFEST}"
require_nonempty_file "${SOURCE_JSON}"
require_nonempty_file "${SOURCE_PACKET}"
[[ "$(sha256 "${SOURCE_PACKET}")" == "${EXPECTED_PACKET_FILE_SHA256}" ]] ||
    fail "corrected GEFV packet file hash mismatch"
[[ "$(byte_count "${SOURCE_PACKET}")" == "${EXPECTED_PACKET_BYTES}" ]] ||
    fail "corrected GEFV packet byte count mismatch"

for manifest in "${BOOT_MANIFEST}" "${STAGE_MANIFEST}"; do
    require_line 'rom_copied_into_checkout=false' "${manifest}"
    require_line 'rom_copied_into_bundle=false' "${manifest}"
    require_line 'private_payloads_copied_into_checkout=false' "${manifest}"
    require_line 'private_payloads_copied_into_bundle=false' "${manifest}"
    require_line "linux_reference_command=${REFERENCE_COMMAND}" "${manifest}"
    require_line "linux_reference_hash_command=${REFERENCE_HASH_COMMAND}" "${manifest}"
    require_line "external_rom_sha1=${ROM_SHA1_EXPECTED}" "${manifest}"
    require_line 'manifest_status=PASS' "${manifest}"
done
require_line 'resource_count=21' "${STAGE_MANIFEST}"

require_line 'manifest_version=6' "${SOURCE_MANIFEST}"
require_line 'magic=GEFV' "${SOURCE_MANIFEST}"
require_line 'goal=native-boot-menu-attract-120' "${SOURCE_MANIFEST}"
require_line 'status=PASS' "${SOURCE_MANIFEST}"
require_line 'runtime_rom_access=false' "${SOURCE_MANIFEST}"
require_line "external_rom_sha1=${ROM_SHA1_EXPECTED}" "${SOURCE_MANIFEST}"
require_line "source_catalog_sha256=${EXPECTED_SOURCE_CATALOG_SHA256}" "${SOURCE_MANIFEST}"
require_line "packet_sha256=${EXPECTED_PACKET_SHA256}" "${SOURCE_MANIFEST}"
require_line "payload_bytes=${EXPECTED_PAYLOAD_BYTES}" "${SOURCE_MANIFEST}"
require_line 'rom_copied_into_checkout=false' "${SOURCE_MANIFEST}"
require_line 'rom_copied_into_bundle=false' "${SOURCE_MANIFEST}"
require_line 'private_payloads_copied_into_checkout=false' "${SOURCE_MANIFEST}"
require_line 'private_payloads_copied_into_bundle=false' "${SOURCE_MANIFEST}"
require_line "record_count=${EXPECTED_RECORD_COUNT}" "${SOURCE_MANIFEST}"
require_line "count_texture_payload=${EXPECTED_TEXTURE_PAYLOAD_COUNT}" "${SOURCE_MANIFEST}"
require_line "count_mip_payload=${EXPECTED_MIP_PAYLOAD_COUNT}" "${SOURCE_MANIFEST}"
require_line "count_tlut_payload=${EXPECTED_TLUT_PAYLOAD_COUNT}" "${SOURCE_MANIFEST}"
require_line "sidecar_count=${EXPECTED_SIDECAR_COUNT}" "${SOURCE_MANIFEST}"

require_line 'status=PASS' "${SOURCE_REPORT}"
require_line 'runtime_rom_access=false' "${SOURCE_REPORT}"
require_line "external_rom_sha1=${ROM_SHA1_EXPECTED}" "${SOURCE_REPORT}"
require_line "packet_sha256=${EXPECTED_PACKET_SHA256}" "${SOURCE_REPORT}"
require_line "payload_bytes=${EXPECTED_PAYLOAD_BYTES}" "${SOURCE_REPORT}"
require_line "record_count=${EXPECTED_RECORD_COUNT}" "${SOURCE_REPORT}"
require_line "texture_payload_records=${EXPECTED_TEXTURE_PAYLOAD_COUNT}" "${SOURCE_REPORT}"
require_line "mip_payload_records=${EXPECTED_MIP_PAYLOAD_COUNT}" "${SOURCE_REPORT}"
require_line "tlut_payload_records=${EXPECTED_TLUT_PAYLOAD_COUNT}" "${SOURCE_REPORT}"
require_line "sidecar_count=${EXPECTED_SIDECAR_COUNT}" "${SOURCE_REPORT}"
require_line 'rom_copied_into_checkout=false' "${SOURCE_REPORT}"
require_line 'rom_copied_into_bundle=false' "${SOURCE_REPORT}"
require_line 'private_payloads_copied_into_checkout=false' "${SOURCE_REPORT}"
require_line 'private_payloads_copied_into_bundle=false' "${SOURCE_REPORT}"

HISTORICAL_SOURCE_ROOT="${PROJECT_ROOT}/${HISTORICAL_SOURCE_ROOT_RELATIVE}"
HISTORICAL_ROOT="${HISTORICAL_SOURCE_ROOT}/${HISTORICAL_RELATIVE_ROOT}"
HISTORICAL_SUMS="${HISTORICAL_SOURCE_ROOT}/${HISTORICAL_RELATIVE_SUMS}"
inside_root "$(realpath_for "${HISTORICAL_SOURCE_ROOT}")" "${PROJECT_ROOT}/build/native" ||
    fail "historical preservation root escapes build/native: ${HISTORICAL_SOURCE_ROOT}"
inside_root "$(realpath_for "${HISTORICAL_ROOT}")" "$(realpath_for "${HISTORICAL_SOURCE_ROOT}")" ||
    fail "historical preservation root escapes its source catalog: ${HISTORICAL_ROOT}"
require_nonempty_file "${HISTORICAL_SUMS}"
require_line "packet_sha256=${EXPECTED_HISTORICAL_PACKET_SHA256}" \
    "${HISTORICAL_ROOT}/source-frontend-v6-manifest.txt"
require_line "packet_sha256=${EXPECTED_HISTORICAL_PACKET_SHA256}" \
    "${HISTORICAL_ROOT}/source-frontend-v6-report.txt"
if ! (cd "${PROJECT_ROOT}" && shasum -a 256 -c "${HISTORICAL_SUMS}") >/dev/null; then
    fail "historical GEFV/GESM preservation manifest verification failed"
fi

# The source-preparation verifier checks packet envelopes, source/path guards,
# payload bounds and all GESM internal hashes without opening the ROM.  Keep it
# in the release gate so a stale sidecar cannot be paired with a fresh GEFV.
python3 "${SOURCE_FRONTEND_V6_SCRIPT}" --verify "${SOURCE_PACKET}" >/dev/null ||
    fail "GEFV packet verification failed"

python3 - "${SOURCE_JSON}" "${SOURCE_FRONTEND_ROOT}" "${EXPECTED_FIXTURE}" <<'PY'
import hashlib
import json
import pathlib
import struct
import sys

manifest_path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
fixture_path = pathlib.Path(sys.argv[3])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
fixture = {}
for line in fixture_path.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    key, value = line.split("=", 1)
    fixture[key] = value
expected_counts = {
    "texture_payload": int(fixture["count_texture_payload"]),
    "mip_payload": int(fixture["count_mip_payload"]),
    "tlut_payload": int(fixture["count_tlut_payload"]),
    "model": int(fixture["count_model"]),
    "node": int(fixture["count_node"]),
    "display_list": int(fixture["count_display_list"]),
    "vertex_group": int(fixture["count_vertex_group"]),
}
if manifest.get("manifest_version") != 6 or manifest.get("magic") != "GEFV":
    raise SystemExit("invalid GEFV manifest identity")
if manifest.get("goal") != "native-boot-menu-attract-120":
    raise SystemExit("invalid GEFV goal")
if manifest.get("runtime_rom_access") is not False:
    raise SystemExit("runtime ROM access is not false")
if manifest.get("external_rom_sha1") != "abe01e4aeb033b6c0836819f549c791b26cfde83":
    raise SystemExit("GEFV external ROM hash mismatch")
if manifest.get("packet_sha256") != fixture["packet_sha256"]:
    raise SystemExit("unexpected final GEFV packet hash")
if manifest.get("source_catalog_sha256") != fixture["source_catalog_sha256"]:
    raise SystemExit("unexpected source catalog hash")
if manifest.get("packet_bytes") != int(fixture["packet_bytes"]):
    raise SystemExit("unexpected final GEFV packet byte count")
if manifest.get("payload_bytes") != int(fixture["payload_bytes"]):
    raise SystemExit("unexpected final GEFV payload byte count")
if manifest.get("record_count", len(manifest.get("records", []))) != int(fixture["record_count"]):
    raise SystemExit("unexpected final GEFV record count")
for key, expected in expected_counts.items():
    if manifest.get("counts", {}).get(key) != expected:
        raise SystemExit(f"GEFV count mismatch for {key}")

expected_sidecars = {
    "chrwppk": ("4c108b4f4ad73a0e158b888d9ef67604319605d622a8146e4d16bb38dd63adfa", 4, 2, 35, 50),
    "goldeneyelogo": ("b73bb84432ad1cd2e821ccc339502a5900571643e0b956ca53d581a5abfee6c1", 3, 1, 162, 438),
    "headbrosnansuit": ("e7e289a79fad192efc99fd90e12933d927bbf3fab827c17bd07721632b647797", 4, 2, 119, 290),
    "legalpage": ("da42f17da9654a83a7c0a7ab3fd3233cc6892434c07cd593227932fb2e545f22", 3, 1, 58, 24),
    "nintendologo": ("a41b43bf4bab4200156296b31b061c858287076ad895abee1e4dcec640693d97", 42, 23, 821, 1363),
    "rarewarelogo": ("5b54353bb0f4dad0a7d314aaf8e6e9673d913d1137507e2f6ba338a0a40bb47d", 0, 9, 389, 397),
    "suitbond": ("c1c1d4e7e87488a40d0998b0c023c863ac21083af186a2ce84be171955545dff", 79, 25, 554, 726),
    "walletbond": ("a50648410b9f8ea8079f4db25078e76657617b779ef996b19a22b6c126b9bd4e", 90, 46, 982, 765),
}
sidecars = {row.get("name"): row for row in manifest.get("sidecars", [])}
if set(sidecars) != set(expected_sidecars):
    raise SystemExit("GEFV sidecar inventory mismatch")
for name, expected in expected_sidecars.items():
    row = sidecars[name]
    if row.get("packet_sha256") != expected[0] or tuple(row.get(k) for k in ("nodes", "display_lists", "commands", "vertices")) != expected[1:]:
        raise SystemExit(f"GESM metadata mismatch for {name}")
    if row.get("unsupported_macros"):
        raise SystemExit(f"GESM unsupported macros for {name}")
    sidecar = root / row.get("path", "")
    if not sidecar.is_file() or not sidecar.stat().st_size:
        raise SystemExit(f"GESM sidecar is missing: {sidecar}")
    # The preparation verifier owns the canonical sidecar hash.  This extra
    # check ensures the manifest's declared byte count cannot describe a
    # different file.
    if row.get("bytes") != sidecar.stat().st_size:
        raise SystemExit(f"GESM byte count mismatch for {name}")

# SELECTFILE is a release-visible frontend texture.  A metadata-only row or a
# zero-filled payload must never satisfy the package gate.
select_name = fixture["selectfile_payload"]
selectfile = next((row for row in manifest.get("records", []) if row.get("name") == select_name and row.get("category") == "texture_payload"), None)
if selectfile is None:
    raise SystemExit("SELECTFILE texture payload is missing")
if selectfile.get("raw_size", 0) <= 0 or selectfile.get("decoded_size", 0) <= 0:
    raise SystemExit("SELECTFILE texture payload has zero size")
if selectfile.get("decoded_sha256") != fixture["selectfile_decoded_sha256"] or selectfile.get("decoded_size") != int(fixture["selectfile_decoded_size"]):
    raise SystemExit("SELECTFILE decoded payload metadata mismatch")
packet_path = root / "source-frontend-v6.gefv"
packet_bytes = packet_path.read_bytes()
header = struct.Struct("<4sIIIIII32s32sI")
if len(packet_bytes) < header.size:
    raise SystemExit("GEFV packet is truncated")
_, _, _, manifest_bytes, _, _, _, _, _, _ = header.unpack_from(packet_bytes)
payload_base = header.size + manifest_bytes
for kind in ("raw", "decoded"):
    offset = int(selectfile.get(f"{kind}_payload_offset", -1))
    size = int(selectfile.get(f"{kind}_size", 0))
    start = payload_base + offset
    payload = packet_bytes[start:start + size]
    if offset < 0 or size <= 0 or len(payload) != size or not any(payload):
        raise SystemExit(f"SELECTFILE {kind} payload is empty or out of bounds")

for path in root.rglob("*"):
    if not path.is_file():
        continue
    if path.suffix.lower() in {".z64", ".n64", ".rom"}:
        raise SystemExit(f"ROM-like payload found in private catalog: {path}")
PY

for sidecar in chrwppk goldeneyelogo headbrosnansuit legalpage nintendologo rarewarelogo suitbond walletbond; do
    python3 "${SOURCE_FRONTEND_V6_SCRIPT}" \
        --verify-sidecar "${SOURCE_FRONTEND_ROOT}/${sidecar}.gesm" >/dev/null ||
        fail "GESM sidecar verification failed: ${sidecar}"
done

if [[ "${MODE}" == "bundle" ]]; then
    [[ -n "${APP_PATH}" ]] || usage
    APP_REAL_PATH=$(realpath_for "${APP_PATH}")
    [[ -d "${APP_PATH}" ]] || fail "application bundle is missing: ${APP_PATH}"
    require_nonempty_file "${APP_PATH}/Contents/MacOS/GoldenEyeHost"
    require_nonempty_file "${APP_PATH}/Contents/Info.plist"
    require_nonempty_file "${APP_PATH}/Contents/Resources/GoldenEyeSourceSceneV6.metallib"
    require_nonempty_file "${APP_PATH}/Contents/Resources/GoldenEyeSource2DV6.metallib"

    # The source-faithful release bundle has exactly the source 3D and source
    # 2D GPU libraries.  The old procedural title and stage-overlay libraries
    # are intentionally not even compiled by build_native_boot.sh; check
    # again at the boundary.
    resource_count=0
    while IFS= read -r -d '' resource; do
        relative="${resource#${APP_PATH}/Contents/Resources/}"
        [[ "${relative}" == "GoldenEyeSourceSceneV6.metallib" ||
           "${relative}" == "GoldenEyeSource2DV6.metallib" ]] ||
            fail "unexpected resource in source-faithful bundle: ${relative}"
        resource_count=$((resource_count + 1))
    done < <(find "${APP_PATH}/Contents/Resources" -type f -print0)
    [[ "${resource_count}" == 2 ]] ||
        fail "source-faithful bundle resource count mismatch: ${resource_count}"

    if find "${APP_PATH}" -type f \( \
        -iname '*.z64' -o -iname '*.n64' -o -iname '*.rom' -o \
        -iname '*.gefv' -o -iname '*.gesm' -o -iname '*.gepk' -o \
        -iname '*.getx' -o -iname '*.bin' -o -iname '*.rz' -o \
        -iname '*.ctl' -o -iname '*.tbl' -o \
        -name 'GoldenEyeTitle.metallib' -o \
        -name 'GoldenEyeStageBackground.metallib' \) \
        -print -quit | grep -q .; then
        fail "ROM/private payload or diagnostic shader found in source-faithful bundle"
    fi

    command -v codesign >/dev/null 2>&1 || fail "codesign is required for bundle validation"
    signature=$(codesign -dv --verbose=4 "${APP_PATH}" 2>&1) ||
        fail "codesign inspection failed"
    printf '%s\n' "${signature}" | grep -q '^Authority=' ||
        fail "application is not signed by a certificate authority"
    if printf '%s\n' "${signature}" | grep -Eiq 'Signature=adhoc|Authority=adhoc'; then
        fail "ad-hoc application signature is forbidden"
    fi
    codesign --verify --deep --strict --verbose=2 "${APP_PATH}" >/dev/null 2>&1 ||
        fail "application code signature verification failed"
fi

printf 'native boot release gate: PASS\n'
printf 'external_rom_sha1=%s\n' "${rom_sha1}"
printf 'source_frontend_root=%s\n' "${SOURCE_FRONTEND_ROOT}"
if [[ "${MODE}" == "bundle" ]]; then
    printf 'source_scene_metallib=present\n'
    printf 'source_2d_metallib=present\n'
    printf 'app=%s\n' "${APP_PATH}"
    printf 'app_real_path=%s\n' "${APP_REAL_PATH}"
else
    printf 'source_scene_metallib=required\n'
    printf 'source_2d_metallib=required\n'
    printf 'package_plan=source-scene-and-source-2d-no-procedural-shaders\n'
fi
if [[ "${DRY_RUN}" == 1 ]]; then
    printf 'dry_run=true\n'
else
    printf 'dry_run=false\n'
fi
