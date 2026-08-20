#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
DEFAULT_ROM_PATH="/Users/derek/Documents/GoldenEye 007 (USA).z64"
ROM_PATH="${1:-${GOLDENEYE_US_ROM:-${DEFAULT_ROM_PATH}}}"
OUTPUT_DIR="${PROJECT_ROOT}/build/native/classic-prop"
MANIFEST_PATH="${OUTPUT_DIR}/classic-prop-manifest.txt"
LOG_PATH="${OUTPUT_DIR}/prepare-classic-prop-asset.log"
REFERENCE_EVIDENCE_PATH="${PROJECT_ROOT}/.porting/m0-provenance.md"

"${SCRIPT_DIR}/prepare_classic_prop_asset.sh" "${ROM_PATH}"

test -f "${MANIFEST_PATH}"
test -f "${LOG_PATH}"
grep -Fqx 'manifest_version=1' "${MANIFEST_PATH}"
grep -Fqx 'asset_name=ammo_crate1' "${MANIFEST_PATH}"
grep -Fqx 'source_row=8052448,576,assets/obseg/prop/Pammo_crate1Z.bin,1,1' "${MANIFEST_PATH}"
grep -Fqx 'external_rom_sha1=abe01e4aeb033b6c0836819f549c791b26cfde83' "${MANIFEST_PATH}"
grep -Fqx "linux_reference_evidence=${REFERENCE_EVIDENCE_PATH}" "${MANIFEST_PATH}"
grep -Fqx 'linux_reference_command=make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1' "${MANIFEST_PATH}"
grep -Fqx 'linux_reference_hash_command=sha1sum -c ge007.u.sha1' "${MANIFEST_PATH}"
grep -Fqx 'compressed_size=576' "${MANIFEST_PATH}"
grep -Fqx 'compressed_sha256=aae993c36f98527510578a5d5b0dd707a54117884385c68ddc781def96af0ec9' "${MANIFEST_PATH}"
grep -Fqx 'binary_size=1488' "${MANIFEST_PATH}"
grep -Fqx 'binary_sha1=2902e2f28defaa2f99e514c12039a731e78072d7' "${MANIFEST_PATH}"
grep -Fqx 'binary_sha256=ca13ff3f26a399767435767fc748cd91027db675ac630d89bfbacc7705b760c9' "${MANIFEST_PATH}"
grep -Fqx 'rom_copied_into_checkout=false' "${MANIFEST_PATH}"
grep -Fqx 'rom_copied_into_bundle=false' "${MANIFEST_PATH}"
grep -Fqx 'manifest_status=PASS' "${LOG_PATH}"

tracked_roms=$(git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64')
test -z "${tracked_roms}"
tracked_prop_assets=$(git -C "${PROJECT_ROOT}" ls-files -- \
    'assets/obseg/prop/Pammo_crate1Z.bin' \
    'assets/images/split/AMMOTEXT765.bin' \
    'assets/images/split/AMMOCRATE1.bin' \
    'assets/images/split/CRATEROPE.bin')
test -z "${tracked_prop_assets}"

test -f "${REFERENCE_EVIDENCE_PATH}"
grep -Fq 'make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1' "${REFERENCE_EVIDENCE_PATH}"
grep -Fq 'sha1sum -c ge007.u.sha1' "${REFERENCE_EVIDENCE_PATH}"
grep -Fq 'abe01e4aeb033b6c0836819f549c791b26cfde83' "${REFERENCE_EVIDENCE_PATH}"

if find "${OUTPUT_DIR}" -type f \( -name '*.z64' -o -name '*.n64' \) -print -quit | grep -q .; then
    echo "ROM-like output found under ${OUTPUT_DIR}" >&2
    exit 1
fi

echo "Classic prop provenance guard: PASS"
echo "Manifest: ${MANIFEST_PATH}"
echo "Log: ${LOG_PATH}"
