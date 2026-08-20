#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

DEFAULT_ROM_PATH="/Users/derek/Documents/GoldenEye 007 (USA).z64"
ROM_PATH_INPUT="${1:-${GOLDENEYE_US_ROM:-${DEFAULT_ROM_PATH}}}"

ROM_SHA1_EXPECTED="abe01e4aeb033b6c0836819f549c791b26cfde83"
ROM_SIZE_EXPECTED=12582912
REFERENCE_EVIDENCE_PATH="${PROJECT_ROOT}/.porting/m0-provenance.md"
REFERENCE_COMMAND='make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1'
REFERENCE_HASH_COMMAND='sha1sum -c ge007.u.sha1'

IMAGELIST_PATH="${PROJECT_ROOT}/imagelist.u.csv"
IMAGES_DEF_PATH="${PROJECT_ROOT}/assets/images.def"
OUTPUT_DIR="${PROJECT_ROOT}/build/native/classic-textures"
PNG_DIR="${OUTPUT_DIR}/png"
TEX2PNG_PATH="${OUTPUT_DIR}/tex2png"
MANIFEST_PATH="${OUTPUT_DIR}/classic-texture-manifest.txt"
LOG_PATH="${OUTPUT_DIR}/prepare-classic-textures.log"

mkdir -p "${OUTPUT_DIR}" "${PNG_DIR}"
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

if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required for bounded PD/PNG metadata validation"
fi

require_exact_line() {
    local expected="$1"
    local path="$2"

    grep -Fqx "${expected}" "${path}" ||
        fail "expected line is missing or changed in ${path}: ${expected}"
}

if [[ ! -f "${ROM_PATH_INPUT}" ]]; then
    fail "external ROM does not exist: ${ROM_PATH_INPUT}"
fi

ROM_DIR=$(cd -- "$(dirname -- "${ROM_PATH_INPUT}")" && pwd -P) ||
    fail "unable to resolve ROM directory: ${ROM_PATH_INPUT}"
ROM_PATH="${ROM_DIR}/$(basename -- "${ROM_PATH_INPUT}")"

if command -v python3 >/dev/null 2>&1; then
    ROM_REAL_PATH=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ROM_PATH}")
else
    ROM_REAL_PATH="${ROM_PATH}"
fi

case "${ROM_REAL_PATH}" in
    "${PROJECT_ROOT}"|"${PROJECT_ROOT}"/*)
        fail "the ROM must remain outside the checkout: ${ROM_REAL_PATH}"
        ;;
esac

[[ -f "${IMAGELIST_PATH}" ]] || fail "canonical image list is missing: ${IMAGELIST_PATH}"
[[ -f "${IMAGES_DEF_PATH}" ]] || fail "canonical image definitions are missing: ${IMAGES_DEF_PATH}"
[[ -f "${REFERENCE_EVIDENCE_PATH}" ]] ||
    fail "Linux reference-build evidence is missing: ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${REFERENCE_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "Linux reference-build command is missing from ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${REFERENCE_HASH_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "Linux reference hash check is missing from ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${ROM_SHA1_EXPECTED}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "expected ROM SHA-1 is missing from ${REFERENCE_EVIDENCE_PATH}"

EXPECTED_IMAGELIST_ROWS=(
    '9430830,1610,assets/images/split/image33.bin,0,1'
    '9437354,1003,assets/images/split/image37.bin,0,1'
    '9438632,551,assets/images/split/image39.bin,0,1'
)
for row in "${EXPECTED_IMAGELIST_ROWS[@]}"; do
    require_exact_line "${row}" "${IMAGELIST_PATH}"
done

EXPECTED_IMAGE_DEF_LINES=(
    'IMAGE(AMMOCRATE1, 0x64A, HIT_WOOD, HIT_WOOD, 0, 0, 0, 0)'
    'IMAGE(CRATEROPE, 0x3EB, HIT_DEFAULT, HIT_DEFAULT, 0, 0, 0, 0)'
    'IMAGE(AMMOTEXT765, 0x227, HIT_DEFAULT, HIT_DEFAULT, 0, 0, 0, 0)'
)
EXPECTED_IMAGE_DEF_IDS=(33 37 39)
for i in "${!EXPECTED_IMAGE_DEF_LINES[@]}"; do
    def_line="$(grep -n -F "${EXPECTED_IMAGE_DEF_LINES[$i]}" "${IMAGES_DEF_PATH}" |
        head -n 1 | cut -d: -f1 || true)"
    [[ -n "${def_line}" ]] ||
        fail "image definition is missing: ${EXPECTED_IMAGE_DEF_LINES[$i]}"
    expected_line_number=$((EXPECTED_IMAGE_DEF_IDS[$i] + 1))
    [[ "${def_line}" == "${expected_line_number}" ]] ||
        fail "image definition ID mismatch for ${EXPECTED_IMAGE_DEF_LINES[$i]}: expected line ${expected_line_number}, got ${def_line}"
    log "image_def_id=${EXPECTED_IMAGE_DEF_IDS[$i]} line=${def_line} value=${EXPECTED_IMAGE_DEF_LINES[$i]}"
done

if ! command -v git >/dev/null 2>&1; then
    fail "git is required for the tracked/private asset provenance guard"
fi
tracked_roms=$(git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64')
[[ -z "${tracked_roms}" ]] || fail "a ROM is tracked by the checkout: ${tracked_roms}"
tracked_private_assets=$(git -C "${PROJECT_ROOT}" ls-files -- \
    'assets/images/split/AMMOCRATE1.bin' \
    'assets/images/split/CRATEROPE.bin' \
    'assets/images/split/AMMOTEXT765.bin')
[[ -z "${tracked_private_assets}" ]] ||
    fail "a private texture payload is tracked by the checkout: ${tracked_private_assets}"
git -C "${PROJECT_ROOT}" check-ignore -q "${OUTPUT_DIR}" ||
    fail "texture output is not ignored: ${OUTPUT_DIR}"

rom_size=$(byte_count "${ROM_PATH}")
[[ "${rom_size}" == "${ROM_SIZE_EXPECTED}" ]] ||
    fail "external ROM size mismatch: expected ${ROM_SIZE_EXPECTED}, got ${rom_size}"
rom_sha1=$(digest sha1 "${ROM_PATH}")
[[ "${rom_sha1}" == "${ROM_SHA1_EXPECTED}" ]] ||
    fail "external ROM SHA-1 mismatch: expected ${ROM_SHA1_EXPECTED}, got ${rom_sha1}"

log "external_rom=${ROM_PATH}"
log "external_rom_real_path=${ROM_REAL_PATH}"
log "external_rom_size=${rom_size}"
log "external_rom_sha1=${rom_sha1}"
log "linux_reference_evidence=${REFERENCE_EVIDENCE_PATH}"
log "linux_reference_command=${REFERENCE_COMMAND}"
log "linux_reference_hash_command=${REFERENCE_HASH_COMMAND}"
log "imagelist_path=${IMAGELIST_PATH}"
log "images_def_path=${IMAGES_DEF_PATH}"
log "output_dir=${OUTPUT_DIR}"
log "rom_copied_into_checkout=false"
log "rom_copied_into_bundle=false"
log "private_payloads_copied_into_checkout=false"
log "private_payloads_copied_into_bundle=false"

# name|id|rom offset|size|sha1|sha256|format|compression|width|height|imagelist row
TEXTURES=(
    'AMMOCRATE1|33|9430830|1610|a6291b4f2b1440cb123475d5f0ae22314402af65|7fefb1b76158430234fd17769798bc58319cb322bd88ae3a979f2bc1b8445ef5|I8|Huffman-blur|64|32|9430830,1610,assets/images/split/image33.bin,0,1'
    'CRATEROPE|37|9437354|1003|b3fa9d916ef81d69fcfbf3e6a2ba8851d3f094ae|4fce6fc79c4f45ba5164e2b31a635e3644b8e535b8bffa46014365bf1c978038|RGBA16-CI8|RZIP palette container|32|32|9437354,1003,assets/images/split/image37.bin,0,1'
    'AMMOTEXT765|39|9438632|551|84785fc84ee5534940959e4fd52827454b404d4b|ec028a7399327a93b2300c42cfac3e1ab133d7ee1804fcd5bdd4b5a0dff05810|IA4|Huffman-lookup|128|16|9438632,551,assets/images/split/image39.bin,0,1'
)

for entry in "${TEXTURES[@]}"; do
    IFS='|' read -r name image_id offset size expected_sha1 expected_sha256 \
        expected_format expected_compression expected_width expected_height imagelist_row <<< "${entry}"
    raw_path="${OUTPUT_DIR}/${name}.bin"
    palette_entries=0
    if [[ "${expected_format}" == "RGBA16-CI8" ]]; then
        palette_entries=256
    fi

    log "extracting=${name} id=${image_id} offset=${offset} size=${size}"
    if ! dd if="${ROM_PATH}" of="${raw_path}" bs=1 skip="${offset}" count="${size}" \
        >/dev/null 2>&1; then
        fail "failed to extract ${name} from the external ROM"
    fi

    actual_size=$(byte_count "${raw_path}")
    [[ "${actual_size}" == "${size}" ]] ||
        fail "${name} size mismatch: expected ${size}, got ${actual_size}"
    actual_sha1=$(digest sha1 "${raw_path}")
    [[ "${actual_sha1}" == "${expected_sha1}" ]] ||
        fail "${name} SHA-1 mismatch: expected ${expected_sha1}, got ${actual_sha1}"
    actual_sha256=$(digest sha256 "${raw_path}")
    [[ "${actual_sha256}" == "${expected_sha256}" ]] ||
        fail "${name} SHA-256 mismatch: expected ${expected_sha256}, got ${actual_sha256}"

    log "${name}_imagelist_row=${imagelist_row}"
    log "${name}_raw_path=${raw_path}"
    log "${name}_raw_size=${actual_size}"
    log "${name}_raw_sha1=${actual_sha1}"
    log "${name}_raw_sha256=${actual_sha256}"
done

if ! command -v cc >/dev/null 2>&1; then
    fail "a C compiler is required to build the tex2png diagnostic"
fi

log "tex2png_source=tools/mktex/src/tex2png.c tools/mktex/src/libpdtex/*.c"
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libpng; then
    if ! cc $(pkg-config --cflags libpng) \
        "${PROJECT_ROOT}/tools/mktex/src/tex2png.c" \
        "${PROJECT_ROOT}/tools/mktex/src/libpdtex/pdtex.c" \
        "${PROJECT_ROOT}/tools/mktex/src/libpdtex/reader.c" \
        "${PROJECT_ROOT}/tools/mktex/src/libpdtex/writer.c" \
        $(pkg-config --libs libpng) -lz -O3 -o "${TEX2PNG_PATH}" \
        >>"${LOG_PATH}" 2>&1; then
        fail "failed to build tex2png with pkg-config libpng"
    fi
elif [[ -f /opt/homebrew/opt/libpng/include/png.h && -d /opt/homebrew/opt/libpng/lib ]]; then
    if ! cc -I/opt/homebrew/opt/libpng/include/libpng16 \
        "${PROJECT_ROOT}/tools/mktex/src/tex2png.c" \
        "${PROJECT_ROOT}/tools/mktex/src/libpdtex/pdtex.c" \
        "${PROJECT_ROOT}/tools/mktex/src/libpdtex/reader.c" \
        "${PROJECT_ROOT}/tools/mktex/src/libpdtex/writer.c" \
        -L/opt/homebrew/opt/libpng/lib -lpng16 -lz -O3 -o "${TEX2PNG_PATH}" \
        >>"${LOG_PATH}" 2>&1; then
        fail "failed to build tex2png with Homebrew libpng"
    fi
else
    if ! cc "${PROJECT_ROOT}/tools/mktex/src/tex2png.c" \
        "${PROJECT_ROOT}/tools/mktex/src/libpdtex/pdtex.c" \
        "${PROJECT_ROOT}/tools/mktex/src/libpdtex/reader.c" \
        "${PROJECT_ROOT}/tools/mktex/src/libpdtex/writer.c" \
        -lpng -lz -O3 -o "${TEX2PNG_PATH}" \
        >>"${LOG_PATH}" 2>&1; then
        fail "failed to build tex2png; install libpng development headers"
    fi
fi
chmod +x "${TEX2PNG_PATH}"
log "tex2png_path=${TEX2PNG_PATH}"

for entry in "${TEXTURES[@]}"; do
    IFS='|' read -r name image_id offset size expected_sha1 expected_sha256 \
        expected_format expected_compression expected_width expected_height imagelist_row <<< "${entry}"
    raw_path="${OUTPUT_DIR}/${name}.bin"
    png_path="${PNG_DIR}/${name}-0.png"
    palette_entries=0
    if [[ "${expected_format}" == "RGBA16-CI8" ]]; then
        palette_entries=256
    fi

    if ! "${TEX2PNG_PATH}" "${raw_path}" "${PNG_DIR}" >>"${LOG_PATH}" 2>&1; then
        fail "tex2png failed to decode ${name}"
    fi
    [[ -f "${png_path}" ]] || fail "tex2png did not create the level-0 PNG for ${name}"

    # Validate the PD header and PNG IHDR without making PNG the runtime asset.
    if ! python3 - "${raw_path}" "${png_path}" "${expected_format}" \
        "${expected_compression}" "${expected_width}" "${expected_height}" \
        "${palette_entries}" <<'PY'
import struct
import sys
from pathlib import Path

raw_path, png_path, expected_format, expected_compression, expected_width, expected_height, expected_palette_entries = sys.argv[1:]
expected_width = int(expected_width)
expected_height = int(expected_height)
expected_palette_entries = int(expected_palette_entries)
raw = Path(raw_path).read_bytes()
bits = ''.join(f'{value:08b}' for value in raw)
cursor = 0

def read_bits(count):
    global cursor
    if cursor + count > len(bits):
        raise ValueError('truncated PD texture header')
    value = int(bits[cursor:cursor + count], 2)
    cursor += count
    return value

read_bits(1)  # has multiple images
is_rzip = read_bits(1)
read_bits(6)  # LOD count
if is_rzip:
    format_id = read_bits(8)
    colour_count = read_bits(8) + 1
    read_bits(colour_count * 16)  # RGBA16/IA palette entries
    width = read_bits(8)
    height = read_bits(8)
    compression = 'RZIP palette container'
    if colour_count != expected_palette_entries:
        raise SystemExit(
            f'PD palette mismatch: got {colour_count}, expected {expected_palette_entries}'
        )
else:
    format_id = read_bits(4)
    width = read_bits(8)
    height = read_bits(8)
    compression_id = read_bits(4)
    compression_names = {
        6: 'Huffman-lookup',
        8: 'Huffman-blur',
    }
    compression = compression_names.get(compression_id, f'compression-{compression_id}')
    if expected_palette_entries != 0:
        raise SystemExit('unexpected palette expectation for a non-RZIP texture')

format_names = {
    6: 'IA4',
    7: 'I8',
    9: 'RGBA16-CI8',
}
format_name = format_names.get(format_id, f'format-{format_id}')
if (format_name, compression, width, height) != (expected_format, expected_compression, expected_width, expected_height):
    raise SystemExit(
        f'PD metadata mismatch: got {format_name}/{compression}/{width}x{height}, '
        f'expected {expected_format}/{expected_compression}/{expected_width}x{expected_height}'
    )

png = Path(png_path).read_bytes()
if png[:8] != b'\x89PNG\r\n\x1a\n' or png[12:16] != b'IHDR':
    raise SystemExit('invalid PNG diagnostic header')
png_width, png_height = struct.unpack('>II', png[16:24])
if (png_width, png_height) != (expected_width, expected_height):
    raise SystemExit(
        f'PNG dimensions mismatch: got {png_width}x{png_height}, '
        f'expected {expected_width}x{expected_height}'
    )
print(f'PD/PNG PASS: {format_name} {compression} {width}x{height}')
PY
    then
        fail "format/dimension validation failed for ${name}"
    fi

    png_size=$(byte_count "${png_path}")
    png_sha256=$(digest sha256 "${png_path}")
    log "${name}_format=${expected_format}"
    log "${name}_compression=${expected_compression}"
    log "${name}_dimensions=${expected_width}x${expected_height}"
    if [[ "${expected_format}" == "RGBA16-CI8" ]]; then
        log "${name}_palette_entries=${palette_entries}"
    fi
    log "${name}_png_path=${png_path}"
    log "${name}_png_size=${png_size}"
    log "${name}_png_sha256=${png_sha256}"
done

if find "${OUTPUT_DIR}" -type f \( -name '*.z64' -o -name '*.n64' -o -name '*.app' \) -print -quit | grep -q .; then
    fail "ROM-like or application-bundle output appeared under ${OUTPUT_DIR}"
fi

{
    printf '%s\n' 'manifest_version=1'
    printf '%s\n' 'asset_family=classic_textures'
    printf 'external_rom_path=%s\n' "${ROM_PATH}"
    printf 'external_rom_size=%s\n' "${rom_size}"
    printf 'external_rom_sha1=%s\n' "${rom_sha1}"
    printf 'linux_reference_evidence=%s\n' "${REFERENCE_EVIDENCE_PATH}"
    printf 'linux_reference_command=%s\n' "${REFERENCE_COMMAND}"
    printf 'linux_reference_hash_command=%s\n' "${REFERENCE_HASH_COMMAND}"
    printf 'imagelist_path=%s\n' "${IMAGELIST_PATH}"
    printf 'images_def_path=%s\n' "${IMAGES_DEF_PATH}"
    printf 'image_def_AMMOCRATE1=%s\n' "${EXPECTED_IMAGE_DEF_LINES[0]}"
    printf 'image_def_CRATEROPE=%s\n' "${EXPECTED_IMAGE_DEF_LINES[1]}"
    printf 'image_def_AMMOTEXT765=%s\n' "${EXPECTED_IMAGE_DEF_LINES[2]}"
    printf 'output_dir=%s\n' "${OUTPUT_DIR}"
    printf '%s\n' 'texture_count=3'
    for entry in "${TEXTURES[@]}"; do
        IFS='|' read -r name image_id offset size expected_sha1 expected_sha256 \
            expected_format expected_compression expected_width expected_height imagelist_row <<< "${entry}"
        raw_path="${OUTPUT_DIR}/${name}.bin"
        png_path="${PNG_DIR}/${name}-0.png"
        palette_entries=0
        if [[ "${expected_format}" == "RGBA16-CI8" ]]; then
            palette_entries=256
        fi
        printf 'texture_%s_id=%s\n' "${name}" "${image_id}"
        printf 'texture_%s_imagelist_row=%s\n' "${name}" "${imagelist_row}"
        printf 'texture_%s_rom_offset=%s\n' "${name}" "${offset}"
        printf 'texture_%s_rom_size=%s\n' "${name}" "${size}"
        printf 'texture_%s_format=%s\n' "${name}" "${expected_format}"
        printf 'texture_%s_compression=%s\n' "${name}" "${expected_compression}"
        printf 'texture_%s_dimensions=%sx%s\n' "${name}" "${expected_width}" "${expected_height}"
        if [[ "${name}" == "CRATEROPE" ]]; then
            printf 'texture_%s_palette_entries=%s\n' "${name}" "${palette_entries}"
        fi
        printf 'texture_%s_raw_path=%s\n' "${name}" "${raw_path}"
        printf 'texture_%s_raw_size=%s\n' "${name}" "$(byte_count "${raw_path}")"
        printf 'texture_%s_raw_sha1=%s\n' "${name}" "$(digest sha1 "${raw_path}")"
        printf 'texture_%s_raw_sha256=%s\n' "${name}" "$(digest sha256 "${raw_path}")"
        printf 'texture_%s_png_path=%s\n' "${name}" "${png_path}"
        printf 'texture_%s_png_size=%s\n' "${name}" "$(byte_count "${png_path}")"
        printf 'texture_%s_png_sha256=%s\n' "${name}" "$(digest sha256 "${png_path}")"
    done
    printf '%s\n' 'rom_copied_into_checkout=false'
    printf '%s\n' 'rom_copied_into_bundle=false'
    printf '%s\n' 'private_payloads_copied_into_checkout=false'
    printf '%s\n' 'private_payloads_copied_into_bundle=false'
    printf '%s\n' 'tracked_rom_guard=pass'
    printf '%s\n' 'tracked_private_asset_guard=pass'
    printf '%s\n' 'diagnostic_png_only=true'
    printf '%s\n' 'manifest_status=PASS'
} > "${MANIFEST_PATH}"

log "manifest_path=${MANIFEST_PATH}"
log "tracked_rom_guard=pass"
log "tracked_private_asset_guard=pass"
log "diagnostic_png_only=true"
log "manifest_status=PASS"
