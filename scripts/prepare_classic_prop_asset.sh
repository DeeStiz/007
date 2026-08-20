#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

DEFAULT_ROM_PATH="/Users/derek/Documents/GoldenEye 007 (USA).z64"
ROM_PATH_INPUT="${1:-${GOLDENEYE_US_ROM:-${DEFAULT_ROM_PATH}}}"

ROM_SHA1_EXPECTED="abe01e4aeb033b6c0836819f549c791b26cfde83"
ROM_SIZE_EXPECTED=12582912
ROM_OFFSET=8052448
ROM_COMPRESSED_SIZE=576
PROP_ROW="8052448,576,assets/obseg/prop/Pammo_crate1Z.bin,1,1"
PROP_BINARY_SIZE_EXPECTED=1488
PROP_BINARY_SHA1_EXPECTED="2902e2f28defaa2f99e514c12039a731e78072d7"
PROP_BINARY_SHA256_EXPECTED="ca13ff3f26a399767435767fc748cd91027db675ac630d89bfbacc7705b760c9"
PROP_COMPRESSED_SHA256_EXPECTED="aae993c36f98527510578a5d5b0dd707a54117884385c68ddc781def96af0ec9"
REFERENCE_EVIDENCE_PATH="${PROJECT_ROOT}/.porting/m0-provenance.md"
REFERENCE_COMMAND='make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1'
REFERENCE_HASH_COMMAND='sha1sum -c ge007.u.sha1'

OUTPUT_DIR="${PROJECT_ROOT}/build/native/classic-prop"
COMPRESSED_PATH="${OUTPUT_DIR}/Pammo_crate1Z.rz"
BINARY_PATH="${OUTPUT_DIR}/Pammo_crate1Z.bin"
MANIFEST_PATH="${OUTPUT_DIR}/classic-prop-manifest.txt"
LOG_PATH="${OUTPUT_DIR}/prepare-classic-prop-asset.log"

mkdir -p "${OUTPUT_DIR}"
: > "${LOG_PATH}"

log() {
    printf '%s\n' "$*" | tee -a "${LOG_PATH}"
}

fail() {
    log "ERROR: $*"
    exit 1
}

digest() {
    local algorithm="$1"
    local path="$2"

    case "${algorithm}" in
        sha1)
            if command -v shasum >/dev/null 2>&1; then
                shasum -a 1 "${path}" | awk '{print $1}'
            elif command -v sha1sum >/dev/null 2>&1; then
                sha1sum "${path}" | awk '{print $1}'
            else
                fail "neither shasum nor sha1sum is available"
            fi
            ;;
        sha256)
            if command -v shasum >/dev/null 2>&1; then
                shasum -a 256 "${path}" | awk '{print $1}'
            elif command -v sha256sum >/dev/null 2>&1; then
                sha256sum "${path}" | awk '{print $1}'
            else
                fail "neither shasum nor sha256sum is available"
            fi
            ;;
        *)
            fail "unsupported digest algorithm: ${algorithm}"
            ;;
    esac
}

byte_count() {
    wc -c < "$1" | tr -d '[:space:]'
}

if [[ ! -f "${ROM_PATH_INPUT}" ]]; then
    fail "external ROM does not exist: ${ROM_PATH_INPUT}"
fi

ROM_DIR=$(cd -- "$(dirname -- "${ROM_PATH_INPUT}")" && pwd -P) || \
    fail "unable to resolve ROM directory: ${ROM_PATH_INPUT}"
ROM_PATH="${ROM_DIR}/$(basename -- "${ROM_PATH_INPUT}")"

case "${ROM_PATH}" in
    "${PROJECT_ROOT}"|"${PROJECT_ROOT}"/*)
        fail "the ROM must remain outside the checkout: ${ROM_PATH}"
        ;;
esac

[[ -f "${PROJECT_ROOT}/scripts/filelist.u.csv" ]] || \
    fail "canonical file list is missing"
[[ -x "${PROJECT_ROOT}/tools/1172inflate.sh" ]] || \
    fail "1172 decompressor is missing or not executable"
[[ -f "${REFERENCE_EVIDENCE_PATH}" ]] || \
    fail "Linux reference-build evidence is missing: ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${REFERENCE_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" || \
    fail "Linux reference-build command is missing from ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${REFERENCE_HASH_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" || \
    fail "Linux reference hash check is missing from ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${ROM_SHA1_EXPECTED}" "${REFERENCE_EVIDENCE_PATH}" || \
    fail "expected ROM SHA-1 is missing from ${REFERENCE_EVIDENCE_PATH}"

if ! grep -Fqx "${PROP_ROW}" "${PROJECT_ROOT}/scripts/filelist.u.csv"; then
    fail "canonical ammo-crate row is missing or changed"
fi

if ! command -v git >/dev/null 2>&1; then
    fail "git is required for the tracked-ROM provenance guard"
fi

tracked_roms=$(git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64')
[[ -z "${tracked_roms}" ]] || fail "a ROM is tracked by the checkout: ${tracked_roms}"

tracked_prop_assets=$(git -C "${PROJECT_ROOT}" ls-files -- \
    'assets/obseg/prop/Pammo_crate1Z.bin' \
    'assets/images/split/AMMOTEXT765.bin' \
    'assets/images/split/AMMOCRATE1.bin' \
    'assets/images/split/CRATEROPE.bin')
[[ -z "${tracked_prop_assets}" ]] || \
    fail "a private prop asset is tracked by the checkout: ${tracked_prop_assets}"

rom_size=$(byte_count "${ROM_PATH}")
[[ "${rom_size}" == "${ROM_SIZE_EXPECTED}" ]] || \
    fail "external ROM size mismatch: expected ${ROM_SIZE_EXPECTED}, got ${rom_size}"
rom_sha1=$(digest sha1 "${ROM_PATH}")
[[ "${rom_sha1}" == "${ROM_SHA1_EXPECTED}" ]] || \
    fail "external ROM SHA-1 mismatch: expected ${ROM_SHA1_EXPECTED}, got ${rom_sha1}"

log "external_rom=${ROM_PATH}"
log "external_rom_size=${rom_size}"
log "external_rom_sha1=${rom_sha1}"
log "canonical_row=${PROP_ROW}"
log "linux_reference_evidence=${REFERENCE_EVIDENCE_PATH}"
log "linux_reference_command=${REFERENCE_COMMAND}"
log "linux_reference_hash_command=${REFERENCE_HASH_COMMAND}"
log "extract_range_offset=${ROM_OFFSET}"
log "extract_range_size=${ROM_COMPRESSED_SIZE}"

if ! dd if="${ROM_PATH}" of="${COMPRESSED_PATH}" bs=1 \
    skip="${ROM_OFFSET}" count="${ROM_COMPRESSED_SIZE}" >>"${LOG_PATH}" 2>&1; then
    fail "failed to extract the canonical compressed prop range"
fi

compressed_size=$(byte_count "${COMPRESSED_PATH}")
[[ "${compressed_size}" == "${ROM_COMPRESSED_SIZE}" ]] || \
    fail "compressed prop size mismatch: expected ${ROM_COMPRESSED_SIZE}, got ${compressed_size}"
compressed_sha256=$(digest sha256 "${COMPRESSED_PATH}")
[[ "${compressed_sha256}" == "${PROP_COMPRESSED_SHA256_EXPECTED}" ]] || \
    fail "compressed prop SHA-256 mismatch: expected ${PROP_COMPRESSED_SHA256_EXPECTED}, got ${compressed_sha256}"

log "compressed_path=${COMPRESSED_PATH}"
log "compressed_size=${compressed_size}"
log "compressed_sha256=${compressed_sha256}"

if ! GZ=gzip "${PROJECT_ROOT}/tools/1172inflate.sh" \
    "${COMPRESSED_PATH}" "${BINARY_PATH}" 2>&1 | tee -a "${LOG_PATH}"; then
    fail "1172 decompression failed"
fi

binary_size=$(byte_count "${BINARY_PATH}")
[[ "${binary_size}" == "${PROP_BINARY_SIZE_EXPECTED}" ]] || \
    fail "decompressed prop size mismatch: expected ${PROP_BINARY_SIZE_EXPECTED}, got ${binary_size}"
binary_sha1=$(digest sha1 "${BINARY_PATH}")
[[ "${binary_sha1}" == "${PROP_BINARY_SHA1_EXPECTED}" ]] || \
    fail "decompressed prop SHA-1 mismatch: expected ${PROP_BINARY_SHA1_EXPECTED}, got ${binary_sha1}"
binary_sha256=$(digest sha256 "${BINARY_PATH}")
[[ "${binary_sha256}" == "${PROP_BINARY_SHA256_EXPECTED}" ]] || \
    fail "decompressed prop SHA-256 mismatch: expected ${PROP_BINARY_SHA256_EXPECTED}, got ${binary_sha256}"

if find "${OUTPUT_DIR}" -type f \( -name '*.z64' -o -name '*.n64' \) -print -quit | grep -q .; then
    fail "a ROM-like file appeared in the native classic-prop output"
fi
if find "${OUTPUT_DIR}" -type d -name '*.app' -print -quit | grep -q .; then
    fail "an application bundle appeared in the native classic-prop output"
fi

{
    printf '%s\n' 'manifest_version=1'
    printf '%s\n' 'asset_name=ammo_crate1'
    printf 'source_row=%s\n' "${PROP_ROW}"
    printf 'external_rom_path=%s\n' "${ROM_PATH}"
    printf 'external_rom_size=%s\n' "${rom_size}"
    printf 'external_rom_sha1=%s\n' "${rom_sha1}"
    printf 'rom_offset=%s\n' "${ROM_OFFSET}"
    printf 'linux_reference_evidence=%s\n' "${REFERENCE_EVIDENCE_PATH}"
    printf 'linux_reference_command=%s\n' "${REFERENCE_COMMAND}"
    printf 'linux_reference_hash_command=%s\n' "${REFERENCE_HASH_COMMAND}"
    printf 'compressed_size=%s\n' "${compressed_size}"
    printf 'compressed_sha256=%s\n' "${compressed_sha256}"
    printf 'binary_path=%s\n' "${BINARY_PATH}"
    printf 'binary_size=%s\n' "${binary_size}"
    printf 'binary_sha1=%s\n' "${binary_sha1}"
    printf 'binary_sha256=%s\n' "${binary_sha256}"
    printf '%s\n' 'rom_copied_into_checkout=false'
    printf '%s\n' 'rom_copied_into_bundle=false'
    printf '%s\n' 'tracked_rom_guard=pass'
    printf '%s\n' 'tracked_asset_guard=pass'
} > "${MANIFEST_PATH}"

log "binary_path=${BINARY_PATH}"
log "binary_size=${binary_size}"
log "binary_sha1=${binary_sha1}"
log "binary_sha256=${binary_sha256}"
log "manifest_path=${MANIFEST_PATH}"
log "bundle_guard=pass"
log "manifest_status=PASS"
