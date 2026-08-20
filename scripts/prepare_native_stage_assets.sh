#!/bin/bash
set -euo pipefail

# Prepare the seven RAMROM-attract stage resource families.  The ROM is an
# explicit external input and is never copied into the checkout or a bundle.
# The generated stage assets and manifest live under ignored build/native
# output and are the only bytes that a future native loader may consume.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

ROM_SHA1_EXPECTED="abe01e4aeb033b6c0836819f549c791b26cfde83"
ROM_SIZE_EXPECTED=12582912
REFERENCE_EVIDENCE_PATH="${PROJECT_ROOT}/.porting/m0-provenance.md"
REFERENCE_COMMAND='make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1'
REFERENCE_HASH_COMMAND='sha1sum -c ge007.u.sha1'
FILELIST_PATH="${PROJECT_ROOT}/scripts/filelist.u.csv"
INFLATE_PATH="${PROJECT_ROOT}/tools/1172inflate.sh"
OUTPUT_DIR="${GOLDENEYE_STAGE_ASSET_OUTPUT_ROOT:-${PROJECT_ROOT}/build/native/stage-assets}"
BACKGROUND_DIR="${OUTPUT_DIR}/background"
STAN_DIR="${OUTPUT_DIR}/stan"
SETUP_DIR="${OUTPUT_DIR}/setup"
MANIFEST_PATH="${OUTPUT_DIR}/stage-assets-manifest.txt"
LOG_PATH="${OUTPUT_DIR}/prepare-native-stage-assets.log"

usage() {
    printf 'Usage: %s /absolute/path/to/GoldenEye-007-US.z64\n' "$0" >&2
    exit 2
}

fail() {
    printf 'ERROR: %s\n' "$*" | tee -a "${LOG_PATH}" >&2
    exit 1
}

digest() {
    local algorithm="$1"
    local path="$2"
    case "${algorithm}" in
        sha1)
            if command -v shasum >/dev/null 2>&1; then
                shasum -a 1 "${path}" | awk '{print $1}'
            else
                sha1sum "${path}" | awk '{print $1}'
            fi
            ;;
        sha256)
            if command -v shasum >/dev/null 2>&1; then
                shasum -a 256 "${path}" | awk '{print $1}'
            else
                sha256sum "${path}" | awk '{print $1}'
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

require_file() {
    [[ -f "$1" ]] || fail "required file is missing: $1"
}

require_exact_line() {
    local expected="$1"
    local path="$2"
    grep -Fqx "${expected}" "${path}" ||
        fail "source row missing or changed: ${expected}"
}

[[ $# -eq 1 ]] || usage
ROM_PATH_INPUT="$1"

mkdir -p "${BACKGROUND_DIR}" "${STAN_DIR}" "${SETUP_DIR}"
: > "${LOG_PATH}"
: > "${MANIFEST_PATH}"

require_file "${ROM_PATH_INPUT}"
require_file "${FILELIST_PATH}"
require_file "${REFERENCE_EVIDENCE_PATH}"
require_file "${INFLATE_PATH}"
[[ -x "${INFLATE_PATH}" ]] || fail "1172 inflater is not executable"

ROM_DIR=$(cd -- "$(dirname -- "${ROM_PATH_INPUT}")" && pwd -P) ||
    fail "unable to resolve external ROM directory"
ROM_PATH="${ROM_DIR}/$(basename -- "${ROM_PATH_INPUT}")"
ROM_REAL_PATH=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' \
    "${ROM_PATH}")
case "${ROM_REAL_PATH}" in
    "${PROJECT_ROOT}"|"${PROJECT_ROOT}"/*)
        fail "the ROM must remain outside the checkout"
        ;;
esac

grep -Fq "${REFERENCE_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "Linux reference-build command is missing"
grep -Fq "${REFERENCE_HASH_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "Linux reference hash command is missing"
grep -Fq "${ROM_SHA1_EXPECTED}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "expected ROM SHA-1 is missing"

git -C "${PROJECT_ROOT}" check-ignore -q "${OUTPUT_DIR}" ||
    fail "stage output is not ignored: ${OUTPUT_DIR}"
tracked_roms=$(git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64' '*.Z64' '*.N64')
[[ -z "${tracked_roms}" ]] || fail "a ROM is tracked by the checkout"
tracked_stage_assets=$(git -C "${PROJECT_ROOT}" ls-files -- \
    'assets/obseg/bg/*.bin' 'assets/obseg/stan/*.bin' \
    'assets/obseg/setup/*.bin' 'assets/obseg/setup/[eju]/*.bin')
[[ -z "${tracked_stage_assets}" ]] || fail "a prepared stage payload is tracked"

rom_size=$(byte_count "${ROM_REAL_PATH}")
[[ "${rom_size}" == "${ROM_SIZE_EXPECTED}" ]] ||
    fail "external ROM size mismatch: expected ${ROM_SIZE_EXPECTED}, got ${rom_size}"
rom_sha1=$(digest sha1 "${ROM_REAL_PATH}")
[[ "${rom_sha1}" == "${ROM_SHA1_EXPECTED}" ]] ||
    fail "external ROM SHA-1 mismatch: expected ${ROM_SHA1_EXPECTED}, got ${rom_sha1}"

printf 'manifest_version=1\n' >> "${MANIFEST_PATH}"
printf 'asset_family=ramrom_stage_resources\n' >> "${MANIFEST_PATH}"
printf 'external_rom_size=%s\n' "${rom_size}" >> "${MANIFEST_PATH}"
printf 'external_rom_sha1=%s\n' "${rom_sha1}" >> "${MANIFEST_PATH}"
printf 'linux_reference_evidence=%s\n' "${REFERENCE_EVIDENCE_PATH}" >> "${MANIFEST_PATH}"
printf 'linux_reference_command=%s\n' "${REFERENCE_COMMAND}" >> "${MANIFEST_PATH}"
printf 'linux_reference_hash_command=%s\n' "${REFERENCE_HASH_COMMAND}" >> "${MANIFEST_PATH}"
printf 'rom_copied_into_checkout=false\n' >> "${MANIFEST_PATH}"
printf 'rom_copied_into_bundle=false\n' >> "${MANIFEST_PATH}"
printf 'private_payloads_copied_into_checkout=false\n' >> "${MANIFEST_PATH}"
printf 'private_payloads_copied_into_bundle=false\n' >> "${MANIFEST_PATH}"

# stage|kind|name|offset|source_bytes|compressed|decoded_bytes|source_sha256|decoded_sha256|file-list row
RESOURCES=(
    'Dam|background|bg_dam_all_p|6290512|197024|0|197024|40f74a2a087fffa6f1d3519d796d2a2989377ee85fd352deb72d774ea76430c0|40f74a2a087fffa6f1d3519d796d2a2989377ee85fd352deb72d774ea76430c0|6290512,197024,assets/obseg/bg/bg_dam_all_p.bin,0,0'
    'Dam|stan|Tbg_dam_all_p_stanZ|8720304|41952|1|89040|c5b5bbc53a949a6548625cb47cac333836bc3ea46b51f7fa477f63a0e004b41a|9a969ef0d2395c35371848235e3576cdbfa1944354806660a4f5243785823cf7|8720304,41952,assets/obseg/stan/Tbg_dam_all_p_stanZ.bin,1,0'
    'Dam|setup|UsetupdamZ|9179344|17104|1|81808|5fcccbab5874f09bfe27f402278188410c00cdaec1bc14487a96d16f5adf4253|b0b900a3e27b2d05cd48590a20c656772434ce4cefbe8955b4fc9b836fd0c23c|9179344,17104,assets/obseg/setup/UsetupdamZ.bin,1,0'
    'Facility|background|bg_ark_all_p|6487536|200576|0|200576|1a70a9b0ab2c8747703b56bcf8cb160ab081bec52f801984fba61093e6d757a6|1a70a9b0ab2c8747703b56bcf8cb160ab081bec52f801984fba61093e6d757a6|6487536,200576,assets/obseg/bg/bg_ark_all_p.bin,0,0'
    'Facility|stan|Tbg_ark_all_p_stanZ|8602016|36800|1|84112|20af8199421905ee6bef99e2d793759328eef6f7f7ea95b718bc88eedcd863bb|6dbc81c99f68e508ecfa84f1c235b8badc27c9502e776c503c6fafedddb2dbee|8602016,36800,assets/obseg/stan/Tbg_ark_all_p_stanZ.bin,1,0'
    'Facility|setup|UsetuparkZ|9107488|15248|1|96160|94d7ee54c20456b5d76534e27d110e60f896c387e07f14bd9cf196ea420404b0|efdeacf9bd5eb8c3a7b5eb4a5d16da0e466eca04b1222606e27cbe559fac4429|9107488,15248,assets/obseg/setup/UsetuparkZ.bin,1,0'
    'Runway|background|bg_run_all_p|6688112|41936|0|41936|8611d916d84ba321766487519c312d4f1a844cf9a4f3e2b427ca795a13f57488|8611d916d84ba321766487519c312d4f1a844cf9a4f3e2b427ca795a13f57488|6688112,41936,assets/obseg/bg/bg_run_all_p.bin,0,0'
    'Runway|stan|Tbg_run_all_p_stanZ|8890736|6784|1|16112|6de6ea7c648f18fc2c6c67c0e5aec4b04a1b077c0de7bc597e3f41754cfa8d62|051b8271552fc59bc9d6ccce84b460936d4a1347d3375f9c192952ddc5de943d|8890736,6784,assets/obseg/stan/Tbg_run_all_p_stanZ.bin,1,0'
    'Runway|setup|UsetuprunZ|9245392|6240|1|31072|2f0c22e1496ff2f761baae7befde091ac783158fcb7dfe0b35ad32453d41e60a|af3cdcc23c7a6e35a0b7697ffbfc2ff2262e247f9913f640b6a51d734b17e3a8|9245392,6240,assets/obseg/setup/UsetuprunZ.bin,1,0'
    'Bunker I|background|bg_sev_all_p|4425312|69104|0|69104|816251f8fea4792633c638d50ea197c52f5b675890b9b24bf780b2bd379bee18|816251f8fea4792633c638d50ea197c52f5b675890b9b24bf780b2bd379bee18|4425312,69104,assets/obseg/bg/bg_sev_all_p.bin,0,0'
    'Bunker I|stan|Tbg_sev_all_p_stanZ|8897520|15824|1|35328|628ea62587ea7ea893eaafce0dc6b7672e3f754e74b17b12b8135af02190815a|d182ed0b41e45fdb7ab635bd8100b65aa559cb1a8d0fe9394941cb259121d0e0|8897520,15824,assets/obseg/stan/Tbg_sev_all_p_stanZ.bin,1,0'
    'Bunker I|setup|UsetupsevbunkerZ|9261456|6704|1|41056|e2abb07ce4b5297a0c91d62d75320ea9f06d089f02f2dc7cf89ec8e87956e7a6|01a79c9ad08b592d9ad12c9319f3e4bf6b0e17d16ee86bacaab3da4fbaafa95a|9261456,6704,assets/obseg/setup/UsetupsevbunkerZ.bin,1,0'
    'Silo|background|bg_silo_all_p|4494416|331584|0|331584|6e250b60ceb8200d9d0f037ca1b8e6457e9f4e03cd67172d1842bac750d8b8a3|6e250b60ceb8200d9d0f037ca1b8e6457e9f4e03cd67172d1842bac750d8b8a3|4494416,331584,assets/obseg/bg/bg_silo_all_p.bin,0,0'
    'Silo|stan|Tbg_silo_all_p_stanZ|8971312|37024|1|83504|c515cef130c40524d4552507c94dddca44d10ee9c1a7ca4664e702f10ae3d6b5|8b25f40ba610ab611d96050fff442b2cdd32882872d1b1cd4286882edb134901|8971312,37024,assets/obseg/stan/Tbg_silo_all_p_stanZ.bin,1,0'
    'Silo|setup|UsetupsiloZ|9301952|10832|1|75136|3d143eeff9ecfd94cb3f75b568c4e4e68e80c793f4d803a7693efda1f9217a8d|e856c85dc01d077889d12a853b09896d50c7b8a83abaeb29fbed376e61fe0fdc|9301952,10832,assets/obseg/setup/u/UsetupsiloZ.bin,1,0'
    'Frigate|background|bg_dest_all_p|5441600|186816|0|186816|3b2fc0ed3b821a32a164a3286eff8bf026729e42be4ca97f69e414e0f6678bca|3b2fc0ed3b821a32a164a3286eff8bf026729e42be4ca97f69e414e0f6678bca|5441600,186816,assets/obseg/bg/bg_dest_all_p.bin,0,0'
    'Frigate|stan|Tbg_dest_all_p_stanZ|8790736|26864|1|61040|e8a398e6f17c5bc8d941fada2e1bf9dc842f36ae07731d2661a2f4867b88fb33|1b9463118f9b2a37b4e4b9c341dd00629781b9585652ea2d2cc39ff3da35500b|8790736,26864,assets/obseg/stan/Tbg_dest_all_p_stanZ.bin,1,0'
    'Frigate|setup|UsetupdestZ|9208624|9040|1|58624|7908d36100ec1a16157bbe1f8b95e7963f147f7b407a1cd83a0172660d5f6069|53ff8828bc49953611f66a2cb14f139cf15ca3802bfb53a14f216000e91a604a|9208624,9040,assets/obseg/setup/u/UsetupdestZ.bin,1,0'
    'Train|background|bg_tra_all_p|5309136|132464|0|132464|30b611e65599f83b13ae5aad5c0ff3fd2dae0cbc07d2d1f8ee7cbf466b7fd3b2|30b611e65599f83b13ae5aad5c0ff3fd2dae0cbc07d2d1f8ee7cbf466b7fd3b2|5309136,132464,assets/obseg/bg/bg_tra_all_p.bin,0,0'
    'Train|stan|Tbg_tra_all_p_stanZ|9028496|9168|1|22336|28206ce592136a18568920339e1a31214a4606e8c77da6cf1b90052f5fd1439a|952f472901aa4db8a3f6804b5efd831c889c9bd5b5b6420ec2552f6a65eabc72|9028496,9168,assets/obseg/stan/Tbg_tra_all_p_stanZ.bin,1,0'
    'Train|setup|UsetuptraZ|9322976|12848|1|82032|bc783d6828c1d19ec1112a3e28c4d7ab8a59ce30f605152f4d3d41b6d41b7f0c|44e77eec6bf815fd6c87f2f1b8efceadbcfbcf4fe1076aef61a99d1e7e8db7f6|9322976,12848,assets/obseg/setup/u/UsetuptraZ.bin,1,0'
)

resource_count=0
for resource in "${RESOURCES[@]}"; do
    IFS='|' read -r stage kind name offset source_bytes compressed decoded_bytes \
        expected_source_sha256 expected_decoded_sha256 source_row <<< "${resource}"
    require_exact_line "${source_row}" "${FILELIST_PATH}"

    case "${kind}" in
        background) resource_dir="${BACKGROUND_DIR}" ;;
        stan) resource_dir="${STAN_DIR}" ;;
        setup) resource_dir="${SETUP_DIR}" ;;
        *) fail "unknown stage resource kind: ${kind}" ;;
    esac

    safe_name="${stage// /_}__${kind}__${name}"
    source_path="${resource_dir}/${safe_name}.bin"
    if [[ "${compressed}" == 1 ]]; then
        source_path="${resource_dir}/${safe_name}.rz"
        decoded_path="${resource_dir}/${safe_name}.bin"
    else
        decoded_path="${source_path}"
    fi

    dd if="${ROM_REAL_PATH}" of="${source_path}" bs=1 skip="${offset}" \
        count="${source_bytes}" status=none ||
        fail "failed to extract ${stage}/${kind}/${name}"
    [[ "$(byte_count "${source_path}")" == "${source_bytes}" ]] ||
        fail "source size mismatch for ${stage}/${kind}/${name}"
    [[ "$(digest sha256 "${source_path}")" == "${expected_source_sha256}" ]] ||
        fail "source SHA-256 mismatch for ${stage}/${kind}/${name}"

    if [[ "${compressed}" == 1 ]]; then
        GZ=gzip "${INFLATE_PATH}" "${source_path}" "${decoded_path}" \
            >> "${LOG_PATH}" 2>&1 || fail "1172 decompression failed for ${name}"
    fi
    [[ "$(byte_count "${decoded_path}")" == "${decoded_bytes}" ]] ||
        fail "decoded size mismatch for ${stage}/${kind}/${name}"
    [[ "$(digest sha256 "${decoded_path}")" == "${expected_decoded_sha256}" ]] ||
        fail "decoded SHA-256 mismatch for ${stage}/${kind}/${name}"

    printf 'resource_%u=%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "${resource_count}" "${stage}" "${kind}" "${name}" "${offset}" \
        "${source_bytes}" "${compressed}" "${decoded_bytes}" \
        "${expected_source_sha256}" "${expected_decoded_sha256}" >> "${MANIFEST_PATH}"
    resource_count=$((resource_count + 1))
done

[[ "${resource_count}" == 21 ]] || fail "stage resource count mismatch"

# The room mappings use the source custom G_SETTEX/G_NOOP producer rather than
# embedding final G_SETTIMG rows.  Trace that producer after all verified
# background payloads exist, then extract/decode only the referenced global
# IMAGE rows into the ignored stage output.  This additive sidecar never
# changes the historical 21-resource manifest or lets runtime open the ROM.
STAGE_TEXTURE_PREP_SCRIPT="${SCRIPT_DIR}/prepare_native_stage_texture_assets.py"
require_file "${STAGE_TEXTURE_PREP_SCRIPT}"
python3 "${STAGE_TEXTURE_PREP_SCRIPT}" \
    --project-root "${PROJECT_ROOT}" \
    --rom "${ROM_REAL_PATH}" \
    --stage-asset-root "${OUTPUT_DIR}" \
    >> "${LOG_PATH}" 2>&1 || fail "stage texture dependency preparation failed"

# Copy the setup-reachable prop and guard model rows through the checked-in
# PitemZ/c_item source include order. This is preparation evidence only; the
# Release scene remains fail-closed until a bounded prop/character lowerer
# consumes the sidecar.
STAGE_SETUP_PREP_SCRIPT="${SCRIPT_DIR}/prepare_native_stage_setup_dependencies.py"
require_file "${STAGE_SETUP_PREP_SCRIPT}"
python3 "${STAGE_SETUP_PREP_SCRIPT}" \
    --project-root "${PROJECT_ROOT}" \
    --rom "${ROM_REAL_PATH}" \
    --stage-asset-root "${OUTPUT_DIR}" \
    >> "${LOG_PATH}" 2>&1 || fail "stage setup dependency preparation failed"

STAGE_MODEL_SIDECAR_SCRIPT="${SCRIPT_DIR}/prepare_native_stage_model_sidecars.py"
require_file "${STAGE_MODEL_SIDECAR_SCRIPT}"
python3 "${STAGE_MODEL_SIDECAR_SCRIPT}" \
    --project-root "${PROJECT_ROOT}" \
    --stage-asset-root "${OUTPUT_DIR}" \
    >> "${LOG_PATH}" 2>&1 || fail "stage model sidecar preparation failed"

if find "${OUTPUT_DIR}" -type f \( -name '*.z64' -o -name '*.n64' -o -name '*.Z64' -o -name '*.N64' \) \
    -print -quit | grep -q .; then
    fail "a ROM-like file appeared under stage output"
fi

printf 'resource_count=%s\n' "${resource_count}" >> "${MANIFEST_PATH}"
printf 'tracked_rom_guard=pass\n' >> "${MANIFEST_PATH}"
printf 'tracked_private_asset_guard=pass\n' >> "${MANIFEST_PATH}"
printf 'manifest_status=PASS\n' >> "${MANIFEST_PATH}"
printf 'manifest_status=PASS\n' >> "${LOG_PATH}"
printf 'Native stage asset preparation: PASS resources=%s\n' "${resource_count}"
printf 'Manifest: %s\n' "${MANIFEST_PATH}"
