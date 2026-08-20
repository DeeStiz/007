#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
DEFAULT_ROM_PATH="/Users/derek/Documents/GoldenEye 007 (USA).z64"
ROM_PATH="${1:-${GOLDENEYE_US_ROM:-${DEFAULT_ROM_PATH}}}"
OUTPUT_DIR="${PROJECT_ROOT}/build/native/classic-textures"
PNG_DIR="${OUTPUT_DIR}/png"
MANIFEST_PATH="${OUTPUT_DIR}/classic-texture-manifest.txt"
LOG_PATH="${OUTPUT_DIR}/prepare-classic-textures.log"
REFERENCE_EVIDENCE_PATH="${PROJECT_ROOT}/.porting/m0-provenance.md"

"${SCRIPT_DIR}/prepare_classic_texture_assets.sh" "${ROM_PATH}"

test -f "${MANIFEST_PATH}"
test -f "${LOG_PATH}"
grep -Fqx 'manifest_version=1' "${MANIFEST_PATH}"
grep -Fqx 'asset_family=classic_textures' "${MANIFEST_PATH}"
grep -Fqx 'external_rom_size=12582912' "${MANIFEST_PATH}"
grep -Fqx 'external_rom_sha1=abe01e4aeb033b6c0836819f549c791b26cfde83' "${MANIFEST_PATH}"
grep -Fqx "linux_reference_evidence=${REFERENCE_EVIDENCE_PATH}" "${MANIFEST_PATH}"
grep -Fqx 'linux_reference_command=make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1' "${MANIFEST_PATH}"
grep -Fqx 'linux_reference_hash_command=sha1sum -c ge007.u.sha1' "${MANIFEST_PATH}"
grep -Fqx 'texture_count=3' "${MANIFEST_PATH}"
grep -Fqx 'image_def_AMMOCRATE1=IMAGE(AMMOCRATE1, 0x64A, HIT_WOOD, HIT_WOOD, 0, 0, 0, 0)' "${MANIFEST_PATH}"
grep -Fqx 'image_def_CRATEROPE=IMAGE(CRATEROPE, 0x3EB, HIT_DEFAULT, HIT_DEFAULT, 0, 0, 0, 0)' "${MANIFEST_PATH}"
grep -Fqx 'image_def_AMMOTEXT765=IMAGE(AMMOTEXT765, 0x227, HIT_DEFAULT, HIT_DEFAULT, 0, 0, 0, 0)' "${MANIFEST_PATH}"

grep -Fqx 'texture_AMMOCRATE1_id=33' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOCRATE1_imagelist_row=9430830,1610,assets/images/split/image33.bin,0,1' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOCRATE1_format=I8' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOCRATE1_compression=Huffman-blur' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOCRATE1_dimensions=64x32' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOCRATE1_raw_size=1610' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOCRATE1_raw_sha1=a6291b4f2b1440cb123475d5f0ae22314402af65' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOCRATE1_raw_sha256=7fefb1b76158430234fd17769798bc58319cb322bd88ae3a979f2bc1b8445ef5' "${MANIFEST_PATH}"

grep -Fqx 'texture_CRATEROPE_id=37' "${MANIFEST_PATH}"
grep -Fqx 'texture_CRATEROPE_imagelist_row=9437354,1003,assets/images/split/image37.bin,0,1' "${MANIFEST_PATH}"
grep -Fqx 'texture_CRATEROPE_format=RGBA16-CI8' "${MANIFEST_PATH}"
grep -Fqx 'texture_CRATEROPE_compression=RZIP palette container' "${MANIFEST_PATH}"
grep -Fqx 'texture_CRATEROPE_dimensions=32x32' "${MANIFEST_PATH}"
grep -Fqx 'texture_CRATEROPE_palette_entries=256' "${MANIFEST_PATH}"
grep -Fqx 'texture_CRATEROPE_raw_size=1003' "${MANIFEST_PATH}"
grep -Fqx 'texture_CRATEROPE_raw_sha1=b3fa9d916ef81d69fcfbf3e6a2ba8851d3f094ae' "${MANIFEST_PATH}"
grep -Fqx 'texture_CRATEROPE_raw_sha256=4fce6fc79c4f45ba5164e2b31a635e3644b8e535b8bffa46014365bf1c978038' "${MANIFEST_PATH}"

grep -Fqx 'texture_AMMOTEXT765_id=39' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOTEXT765_imagelist_row=9438632,551,assets/images/split/image39.bin,0,1' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOTEXT765_format=IA4' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOTEXT765_compression=Huffman-lookup' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOTEXT765_dimensions=128x16' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOTEXT765_raw_size=551' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOTEXT765_raw_sha1=84785fc84ee5534940959e4fd52827454b404d4b' "${MANIFEST_PATH}"
grep -Fqx 'texture_AMMOTEXT765_raw_sha256=ec028a7399327a93b2300c42cfac3e1ab133d7ee1804fcd5bdd4b5a0dff05810' "${MANIFEST_PATH}"

grep -Fqx 'rom_copied_into_checkout=false' "${MANIFEST_PATH}"
grep -Fqx 'rom_copied_into_bundle=false' "${MANIFEST_PATH}"
grep -Fqx 'private_payloads_copied_into_checkout=false' "${MANIFEST_PATH}"
grep -Fqx 'private_payloads_copied_into_bundle=false' "${MANIFEST_PATH}"
grep -Fqx 'tracked_rom_guard=pass' "${MANIFEST_PATH}"
grep -Fqx 'tracked_private_asset_guard=pass' "${MANIFEST_PATH}"
grep -Fqx 'diagnostic_png_only=true' "${MANIFEST_PATH}"
grep -Fqx 'manifest_status=PASS' "${MANIFEST_PATH}"
grep -Fqx 'manifest_status=PASS' "${LOG_PATH}"

test -x "${OUTPUT_DIR}/tex2png"
test -f "${OUTPUT_DIR}/AMMOCRATE1.bin"
test -f "${OUTPUT_DIR}/CRATEROPE.bin"
test -f "${OUTPUT_DIR}/AMMOTEXT765.bin"
test -f "${PNG_DIR}/AMMOCRATE1-0.png"
test -f "${PNG_DIR}/CRATEROPE-0.png"
test -f "${PNG_DIR}/AMMOTEXT765-0.png"

tracked_roms=$(git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64')
test -z "${tracked_roms}"
tracked_private_assets=$(git -C "${PROJECT_ROOT}" ls-files -- \
    'assets/images/split/AMMOCRATE1.bin' \
    'assets/images/split/CRATEROPE.bin' \
    'assets/images/split/AMMOTEXT765.bin')
test -z "${tracked_private_assets}"
git -C "${PROJECT_ROOT}" check-ignore -q "${OUTPUT_DIR}"

if find "${OUTPUT_DIR}" -type f \( -name '*.z64' -o -name '*.n64' -o -name '*.app' \) -print -quit | grep -q .; then
    echo "ROM-like or application-bundle output found under ${OUTPUT_DIR}" >&2
    exit 1
fi

test -f "${REFERENCE_EVIDENCE_PATH}"
grep -Fq 'make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1' "${REFERENCE_EVIDENCE_PATH}"
grep -Fq 'sha1sum -c ge007.u.sha1' "${REFERENCE_EVIDENCE_PATH}"
grep -Fq 'abe01e4aeb033b6c0836819f549c791b26cfde83' "${REFERENCE_EVIDENCE_PATH}"

echo "Classic texture provenance and tex2png diagnostics: PASS"
echo "Manifest: ${MANIFEST_PATH}"
echo "Log: ${LOG_PATH}"
