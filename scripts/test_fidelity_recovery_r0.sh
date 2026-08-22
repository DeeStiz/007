#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
OUTPUT_DIR="${PROJECT_ROOT}/build/native/fidelity-recovery"
REFERENCE_EVIDENCE="${PROJECT_ROOT}/.porting/m0-provenance.md"
BASELINE_DOC="${PROJECT_ROOT}/.porting/fidelity-recovery-r0-baseline.md"
ROM_PATH="${GOLDENEYE_US_ROM:-/Users/derek/Documents/GoldenEye 007 (USA).z64}"

mkdir -p "${OUTPUT_DIR}"

LOG_PATH="${OUTPUT_DIR}/r0-guard.log"
STATUS_PATH="${OUTPUT_DIR}/dirty-status.txt"
HEADER_PATH="${OUTPUT_DIR}/v5-public-header-sha256.txt"
LAYOUT_PATH="${OUTPUT_DIR}/v5-layout.txt"
BUNDLE_PATH="${OUTPUT_DIR}/bundle-boundary.txt"
HASH_PATH="${OUTPUT_DIR}/frozen-v1-v4.txt"
MANIFEST_PATH="${OUTPUT_DIR}/r0-manifest.txt"

fail() {
    echo "fidelity recovery R0 guard: $*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

require_nonempty() {
    require_file "$1"
    [[ -s "$1" ]] || fail "empty file: $1"
}

require_line() {
    local expected="$1"
    local path="$2"
    grep -Fqx "${expected}" "${path}" ||
        fail "missing exact line in ${path}: ${expected}"
}

digest_sha1() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 1 "$1" | awk '{print $1}'
    else
        sha1sum "$1" | awk '{print $1}'
    fi
}

digest_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

relative_path() {
    python3 - "$PROJECT_ROOT" "$1" <<'PY'
import os
import sys
print(os.path.relpath(os.path.realpath(sys.argv[2]), sys.argv[1]))
PY
}

[[ -f "${BASELINE_DOC}" ]] || fail "R0 baseline document is missing"
[[ -d "${PROJECT_ROOT}/.git" ]] || fail "checkout metadata is missing"

# Capture the current status before this guard writes its own ignored output.
# Sorting makes this snapshot deterministic for a fixed worktree.
git -C "${PROJECT_ROOT}" status --short --untracked-files=all | LC_ALL=C sort \
    > "${STATUS_PATH}"
STATUS_SHA256=$(digest_sha256 "${STATUS_PATH}")
if [[ -s "${STATUS_PATH}" ]]; then
    STATUS_STATE=dirty
else
    # A clean committed checkout is a valid provenance input.  Keep the empty
    # status capture and record the state explicitly so this does not weaken
    # any of the ROM, frozen-contract, ABI, or bundle-boundary checks below.
    STATUS_STATE=clean
fi

echo "[R0] status state=${STATUS_STATE} entries=$(wc -l < "${STATUS_PATH}" | tr -d '[:space:]') sha256=${STATUS_SHA256}" \
    > "${LOG_PATH}"

echo "[R0] checking frozen V1/V2/V3/V4 evidence" | tee -a "${LOG_PATH}"
FROZEN_LOG_V1_V3="${PROJECT_ROOT}/build/native/classic-textures/texture-replay-smoke.log"
FROZEN_LOG_V4="${PROJECT_ROOT}/build/native/classic-combiner/classic-combiner-run-a.log"
require_nonempty "${FROZEN_LOG_V1_V3}"
require_nonempty "${FROZEN_LOG_V4}"

FROZEN_LINES=(
    'v1=1522029846112142469'
    'v2Packet=65363635960931316'
    'v2Event=905714786767796339'
    'v2State=10439205544326414085'
    'v3Packet=11580554792388204033'
    'v3Event=9845751795158270468'
    'v3Material=14168780479827987350'
    'v4Setup=6213740136672363482'
    'v4Event=5747731189711370311'
    'v4Key=16733630809188353388'
)

require_line 'V1/V2 regression hashes: PASS v1=1522029846112142469 v2Packet=65363635960931316 v2Event=905714786767796339 v2State=10439205544326414085' \
    "${FROZEN_LOG_V1_V3}"
require_line 'textured replay: PASS path=/Users/derek/Developer/goldeneye-swift/build/native/classic-prop/Pammo_crate1Z.bin commands=24 draws=4 vertices=40 triangles=20 packetHash=11580554792388204033 eventHash=9845751795158270468 materialHash=14168780479827987350' \
    "${FROZEN_LOG_V1_V3}"
require_line 'classic combiner: PASS commands=22 setup=3 draws=4 setupHash=6213740136672363482 eventHash=5747731189711370311 keyHash=16733630809188353388' \
    "${FROZEN_LOG_V4}"

printf '%s\n' "${FROZEN_LINES[@]}" > "${HASH_PATH}"
printf '%s\n' "${FROZEN_LINES[@]}" | while IFS= read -r line; do
    echo "[R0] frozen ${line}" >> "${LOG_PATH}"
done

echo "[R0] checking Linux reference evidence and ROM boundary" | tee -a "${LOG_PATH}"
require_nonempty "${REFERENCE_EVIDENCE}"
grep -Fq 'make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1' \
    "${REFERENCE_EVIDENCE}" || fail "Linux reference build command is absent"
grep -Fq 'sha1sum -c ge007.u.sha1' "${REFERENCE_EVIDENCE}" ||
    fail "Linux reference hash command is absent"
grep -Fq 'abe01e4aeb033b6c0836819f549c791b26cfde83' \
    "${REFERENCE_EVIDENCE}" || fail "reference ROM SHA-1 is absent"

ROM_REAL_PATH=$(python3 - "${ROM_PATH}" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
)
[[ -f "${ROM_REAL_PATH}" ]] || fail "external ROM is missing: ${ROM_REAL_PATH}"
case "${ROM_REAL_PATH}" in
    "${PROJECT_ROOT}"|"${PROJECT_ROOT}"/*)
        fail "external ROM is inside checkout: ${ROM_REAL_PATH}"
        ;;
esac
ROM_SIZE=$(wc -c < "${ROM_REAL_PATH}" | tr -d '[:space:]')
[[ "${ROM_SIZE}" == "12582912" ]] ||
    fail "external ROM size mismatch: ${ROM_SIZE}"
ROM_SHA1=$(digest_sha1 "${ROM_REAL_PATH}")
[[ "${ROM_SHA1}" == "abe01e4aeb033b6c0836819f549c791b26cfde83" ]] ||
    fail "external ROM SHA-1 mismatch: ${ROM_SHA1}"
printf '%s\n' \
    "external_rom_path=${ROM_REAL_PATH}" \
    "external_rom_inside_checkout=false" \
    "external_rom_size=${ROM_SIZE}" \
    "external_rom_sha1=${ROM_SHA1}" >> "${LOG_PATH}"

if git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64' '*.Z64' '*.N64' |
    grep -q .; then
    fail "a ROM is tracked by Git"
fi
if git -C "${PROJECT_ROOT}" ls-files -- \
    'assets/obseg/prop/Pammo_crate1Z.bin' \
    'assets/images/split/AMMOCRATE1.bin' \
    'assets/images/split/AMMOTEXT765.bin' \
    'assets/images/split/CRATEROPE.bin' | grep -q .; then
    fail "a private extracted payload is tracked by Git"
fi

git -C "${PROJECT_ROOT}" check-ignore -q "${OUTPUT_DIR}" ||
    fail "R0 output directory is not ignored"
if git -C "${PROJECT_ROOT}" ls-files -- "build/native/fidelity-recovery" |
    grep -q .; then
    fail "R0 output directory contains a tracked path"
fi

# Runtime source may mention N64 semantics, but it must not contain a literal
# ROM path or ROM-file open target. Preparation scripts remain outside this
# check because they are the explicitly authorized external-input boundary.
if rg -n -i --glob '*.swift' --glob '*.c' --glob '*.m' \
    '(goldeneye[^[:space:]]*\.(z64|n64)|[^[:space:]]+\.(z64|n64))' \
    "${PROJECT_ROOT}/native/host" "${PROJECT_ROOT}/native/src"; then
    fail "runtime source contains a ROM-file literal"
fi

echo "[R0] checking immutable V5 public headers" | tee -a "${LOG_PATH}"
V5_HEADERS=(
    native/include/ge_audio_engine_v5.h
    native/include/ge_audio_output_v5.h
    native/include/ge_audio_source_node_v5.h
    native/include/ge_audio_v5.h
    native/include/ge_classic_raster_v5.h
    native/include/ge_native_runtime_v5.h
    native/include/ge_ramrom_playback_v5.h
    native/include/ge_ramrom_v5.h
    native/include/ge_stage_v5.h
    native/include/ge_title_raster_v5.h
    native/include/ge_title_route_v5.h
    native/include/ge_native_foundation.h
)
EXPECTED_HEADERS=$(cat <<'EOF'
ec530ddedde1c12527279609a8acdfb043aeb517120e90544d8c0e69278db5e3  native/include/ge_audio_engine_v5.h
b6a74fb2e847fddfebbeb769e8e88a87a8e10e81418fa44c489ac107c1ffb549  native/include/ge_audio_output_v5.h
6c833ce78c969fa55a8ffc32c6c62a4b77d83119f36803bc5c9b2bff620c5644  native/include/ge_audio_source_node_v5.h
403fb3b3a15a67e02fc6ec28793e61d46ec3968941212610ce51018c63ba6868  native/include/ge_audio_v5.h
510957f05f8ab1127e42f5526b3759b4dd4d9e022beac3554f21f0277fb38391  native/include/ge_classic_raster_v5.h
de83712f434e94c33dcfffdfa80831b695fbfcbf2eb313fbbcd716af943f6cde  native/include/ge_native_runtime_v5.h
71f5f75b4e765508ae2bff18ed0cca2da10a4aa3d9b4660c95619ac4678f83e5  native/include/ge_ramrom_playback_v5.h
4d0514069fba55ecfe072150bddd3f0849761e1968f7c9e84b534cb6663d2f0c  native/include/ge_ramrom_v5.h
da5cafd87734d0c921f7fe6756a1bbf21cb5d5cc86272f16489b73e2e9812534  native/include/ge_stage_v5.h
988fce12a477ec3c7b337dbcde8077520919eaaab35546cb1bf6ff167e2f80ca  native/include/ge_title_raster_v5.h
e8a3af485980f90d0d47a1a1b0bf60090bd8cdb2c097bd1eb990378419fe6c97  native/include/ge_title_route_v5.h
2979dc66b760cb5d572c4e494737c16693fff8dec390ab5a6b87c4eaeec7e80d  native/include/ge_native_foundation.h
EOF
)
printf '%s\n' "${EXPECTED_HEADERS}" > "${HEADER_PATH}"
for header in "${V5_HEADERS[@]}"; do
    require_file "${PROJECT_ROOT}/${header}"
    digest=$(digest_sha256 "${PROJECT_ROOT}/${header}")
    expected=$(printf '%s\n' "${EXPECTED_HEADERS}" |
        awk -v path="${header}" '$2 == path { print $1 }')
    [[ "${digest}" == "${expected}" ]] ||
        fail "V5 header hash changed: ${header} (${digest})"
done

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ge-fidelity-r0.XXXXXX")
trap 'rm -rf "${TMP_DIR}"' EXIT
PROBE="${TMP_DIR}/v5_layout_probe"
if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    TARGET_ARGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}")
else
    CC=${CC:-clang}
    TARGET_ARGS=()
fi

"${CC}" -std=c11 -Wall -Wextra -Werror -I "${PROJECT_ROOT}/native/include" \
    "${TARGET_ARGS[@]}" -x c - -o "${PROBE}" <<'EOF'
#include <stdio.h>
#include "ge_native_foundation.h"
#include "ge_audio_engine_v5.h"
#include "ge_audio_output_v5.h"
#include "ge_audio_source_node_v5.h"
#include "ge_audio_v5.h"
#include "ge_classic_raster_v5.h"
#include "ge_native_runtime_v5.h"
#include "ge_ramrom_playback_v5.h"
#include "ge_ramrom_v5.h"
#include "ge_stage_v5.h"
#include "ge_title_raster_v5.h"
#include "ge_title_route_v5.h"
#define P(T) printf("%s=%zu\n", #T, sizeof(T))
int main(void) {
 P(GEAbiHeaderV1);
 P(GEAudioDiagnosticV5); P(GECSeqInfoV5); P(GECSeqLoopStateV5); P(GECSeqStateV5); P(GECSeqEventV5); P(GEAudioSchedulerV5); P(GEAudioWaveV5); P(GEAudioBankV5); P(GEAudioVoiceV5); P(GEAudioSynthV5); P(GEAudioRenderResultV5);
 P(GEAudioPCMSourceSnapshotV5); P(GEAudioPCMSourceV5); P(GEAudioPCMRefillResultV5); P(GEAudioPCMReadResultV5);
 P(GEAudioAssetV5); P(GEAudioEventV5); P(GEAudioPCMBlockV5); P(GEAudioSnapshotV5); P(GEAudioClockV5);
 P(GEClassicRasterStateV5); P(GEClassicRasterInputV5); P(GEClassicRasterResultV5);
 P(GETimebaseConfigV5); P(GEInputEventV5); P(GEInputSnapshotV5); P(GETitleParitySnapshotV5); P(GESceneFrameV5); P(GEScenePageV5); P(GEAudioCommandV5); P(GERamRomSnapshotV5);
 P(GERamRomPlaybackInstallV5); P(GERamRomPlaybackInputV5); P(GERamRomPlaybackEventV5); P(GERamRomPlaybackStateV5);
 P(GERamRomHeaderV5); P(GERamRomPacketV5); P(GERamRomSampleV5); P(GERamRomParseSummaryV5); P(GERamRomCatalogEntryV5);
 P(GEStageDiagnosticV5); P(GEStageResourceV5); P(GEStageCatalogEntryV5); P(GEStage1172InfoV5); P(GEStageAssetViewV5); P(GEStageResourcePacketV5); P(GEStageResourceViewV5); P(GEStageBackgroundV5); P(GEStageBackgroundRoomV5);
 P(GETitleRasterSourceStateV5); P(GETitleRasterStateV5); P(GETitleRasterInputV5); P(GETitleRasterResultV5);
 P(GETitleRouteCastEntryV5); P(GETitleRouteCastInputV5); P(GETitleRouteCastDecisionV5); P(GETitleRouteDemoSelectionV5); P(GETitleRouteRestorePointV5);
 return 0;
}
EOF

EXPECTED_LAYOUT=$(sed -n '/^GEAbiHeaderV1=/,/^GETitleRouteRestorePointV5=/p' "${BASELINE_DOC}" |
    sed -n '/^GEAbiHeaderV1=/,/^GETitleRouteRestorePointV5=/p')
if [[ -z "${EXPECTED_LAYOUT}" ]]; then
    # The checked-in baseline keeps the canonical layout block in a fenced
    # code section. Keep the expected values here as a second fail-closed
    # source so a formatting-only document edit cannot disable the guard.
    EXPECTED_LAYOUT=$(cat <<'EOF'
GEAbiHeaderV1=8
GEAudioDiagnosticV5=128
GECSeqInfoV5=32
GECSeqLoopStateV5=12
GECSeqStateV5=3340
GECSeqEventV5=56
GEAudioSchedulerV5=3392
GEAudioWaveV5=76
GEAudioBankV5=36
GEAudioVoiceV5=131164
GEAudioSynthV5=3148120
GEAudioRenderResultV5=80
GEAudioPCMSourceSnapshotV5=72
GEAudioPCMSourceV5=32848
GEAudioPCMRefillResultV5=64
GEAudioPCMReadResultV5=64
GEAudioAssetV5=104
GEAudioEventV5=56
GEAudioPCMBlockV5=64
GEAudioSnapshotV5=88
GEAudioClockV5=40
GEClassicRasterStateV5=104
GEClassicRasterInputV5=28
GEClassicRasterResultV5=240
GETimebaseConfigV5=56
GEInputEventV5=64
GEInputSnapshotV5=88
GETitleParitySnapshotV5=136
GESceneFrameV5=120
GEScenePageV5=56
GEAudioCommandV5=88
GERamRomSnapshotV5=128
GERamRomPlaybackInstallV5=320
GERamRomPlaybackInputV5=40
GERamRomPlaybackEventV5=168
GERamRomPlaybackStateV5=472
GERamRomHeaderV5=184
GERamRomPacketV5=80
GERamRomSampleV5=36
GERamRomParseSummaryV5=104
GERamRomCatalogEntryV5=48
GEStageDiagnosticV5=132
GEStageResourceV5=100
GEStageCatalogEntryV5=348
GEStage1172InfoV5=48
GEStageAssetViewV5=64
GEStageResourcePacketV5=120
GEStageResourceViewV5=64
GEStageBackgroundV5=112
GEStageBackgroundRoomV5=96
GETitleRasterSourceStateV5=24
GETitleRasterStateV5=112
GETitleRasterInputV5=208
GETitleRasterResultV5=928
GETitleRouteCastEntryV5=32
GETitleRouteCastInputV5=52
GETitleRouteCastDecisionV5=40
GETitleRouteDemoSelectionV5=80
GETitleRouteRestorePointV5=48
EOF
)
fi
printf '%s\n' "${EXPECTED_LAYOUT}" > "${LAYOUT_PATH}.expected"
"${PROBE}" > "${LAYOUT_PATH}"
diff -u "${LAYOUT_PATH}.expected" "${LAYOUT_PATH}" ||
    fail "V5 C layout snapshot changed"
rm -f "${LAYOUT_PATH}.expected"

echo "[R0] checking application bundle/private-payload boundaries" | tee -a "${LOG_PATH}"
BUNDLES=()
while IFS= read -r bundle; do
    [[ -n "${bundle}" ]] && BUNDLES+=("${bundle}")
done < <(find "${PROJECT_ROOT}/build/native" -type d -name '*.app' -print | LC_ALL=C sort)
[[ "${#BUNDLES[@]}" -gt 0 ]] || fail "no native app bundle found"
: > "${BUNDLE_PATH}"
for bundle in "${BUNDLES[@]}"; do
    executable_name=$(plutil -extract CFBundleExecutable raw -o - \
        "${bundle}/Contents/Info.plist" 2>/dev/null || true)
    if [[ -z "${executable_name}" ]]; then
        executable_name=$(basename "${bundle}" .app)
    fi
    [[ -f "${bundle}/Contents/MacOS/${executable_name}" ]] ||
        fail "bundle executable missing: ${bundle}"
    printf 'bundle=%s\n' "$(relative_path "${bundle}")" >> "${BUNDLE_PATH}"
    private_files=$(find "${bundle}" -type f \
        \( -iname '*.z64' -o -iname '*.n64' -o -iname '*.bin' -o -iname '*.rz' \
        -o -iname '*.ctl' -o -iname '*.tbl' -o -iname '*.seq' \) -print)
    if [[ -n "${private_files}" ]]; then
        printf '%s\n' "${private_files}" >> "${BUNDLE_PATH}"
        fail "private payload found in app bundle: ${bundle}"
    fi
    printf 'private_payloads=none\n' >> "${BUNDLE_PATH}"
done

cat > "${MANIFEST_PATH}" <<EOF
status_entries=$(wc -l < "${STATUS_PATH}" | tr -d '[:space:]')
status_state=${STATUS_STATE}
status_sha256=${STATUS_SHA256}
rom_path=${ROM_REAL_PATH}
rom_inside_checkout=false
rom_size=${ROM_SIZE}
rom_sha1=${ROM_SHA1}
linux_reference_evidence=$(relative_path "${REFERENCE_EVIDENCE}")
v5_header_manifest=$(relative_path "${HEADER_PATH}")
v5_layout_manifest=$(relative_path "${LAYOUT_PATH}")
bundle_manifest=$(relative_path "${BUNDLE_PATH}")
private_payloads_in_bundles=false
runtime_rom_literal=false
EOF

echo "[R0] PASS" | tee -a "${LOG_PATH}"
