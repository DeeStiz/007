#!/bin/bash
set -euo pipefail

# Prepare only the title/audio inputs needed by the native boot vertical
# slice.  The ROM is an explicit external input and is never copied into the
# checkout or an application bundle.  Every generated payload is ignored
# build output and is accepted only after its source and decoded hashes match
# this manifest.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

ROM_SHA1_EXPECTED="abe01e4aeb033b6c0836819f549c791b26cfde83"
ROM_SIZE_EXPECTED=12582912
REFERENCE_EVIDENCE_PATH="${PROJECT_ROOT}/.porting/m0-provenance.md"
REFERENCE_COMMAND='make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1'
REFERENCE_HASH_COMMAND='sha1sum -c ge007.u.sha1'
FILELIST_PATH="${PROJECT_ROOT}/scripts/filelist.u.csv"
INFLATE_PATH="${PROJECT_ROOT}/tools/1172inflate.sh"

OUTPUT_DIR="${PROJECT_ROOT}/build/native/boot-assets"
TITLE_DIR="${OUTPUT_DIR}/title"
AUDIO_DIR="${OUTPUT_DIR}/audio"
RAMROM_DIR="${OUTPUT_DIR}/ramrom"
MANIFEST_PATH="${OUTPUT_DIR}/native-boot-assets-manifest.txt"
LOG_PATH="${OUTPUT_DIR}/prepare-native-boot-assets.log"
SOURCE_FRONTEND_V6_SCRIPT="${SCRIPT_DIR}/prepare_native_source_frontend_v6.py"
SOURCE_FRONTEND_V6_DIR="${PROJECT_ROOT}/build/native/source-frontend-v6-image-decoder-v6"
SOURCE_FRONTEND_V6_REPORT="${SOURCE_FRONTEND_V6_DIR}/source-frontend-v6-report.txt"
PRESERVED_LEGACY_SOURCE_FRONTEND_V6_DIR="${PROJECT_ROOT}/build/native/source-frontend-v6"
PRESERVED_LEGACY_SOURCE_FRONTEND_V6_PACKET="${PRESERVED_LEGACY_SOURCE_FRONTEND_V6_DIR}/source-frontend-v6.gefv"
PRESERVED_LEGACY_SOURCE_FRONTEND_V6_PACKET_SHA256="5aca3e17ec9f3298f1ea207f1b5fca030a5dc77e17747abf88127e3922e2b9cd"

usage() {
    printf 'Usage: %s /absolute/path/to/GoldenEye-007-US.z64\n' "$0" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage
ROM_PATH_INPUT="$1"

mkdir -p "${TITLE_DIR}" "${AUDIO_DIR}" "${RAMROM_DIR}"
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

require_file() {
    [[ -f "$1" ]] || fail "required file is missing: $1"
}

require_exact_line() {
    local expected="$1"
    local path="$2"
    grep -Fqx "${expected}" "${path}" ||
        fail "expected exact line is missing or changed in ${path}: ${expected}"
}

direct_asset_path() {
    local group_dir="$1"
    local name="$2"
    case "${name}" in
        *.ctl|*.tbl) printf '%s/%s\n' "${group_dir}" "${name}" ;;
        *) printf '%s/%s.bin\n' "${group_dir}" "${name}" ;;
    esac
}

if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required for external-path validation"
fi
if ! command -v git >/dev/null 2>&1; then
    fail "git is required for tracked/private asset guards"
fi
require_file "${ROM_PATH_INPUT}"
require_file "${FILELIST_PATH}"
require_file "${REFERENCE_EVIDENCE_PATH}"
require_file "${INFLATE_PATH}"
[[ -x "${INFLATE_PATH}" ]] || fail "1172 inflater is not executable: ${INFLATE_PATH}"

ROM_DIR=$(cd -- "$(dirname -- "${ROM_PATH_INPUT}")" && pwd -P) ||
    fail "unable to resolve external ROM directory: ${ROM_PATH_INPUT}"
ROM_PATH="${ROM_DIR}/$(basename -- "${ROM_PATH_INPUT}")"
ROM_REAL_PATH=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' \
    "${ROM_PATH}")
case "${ROM_REAL_PATH}" in
    "${PROJECT_ROOT}"|"${PROJECT_ROOT}"/*)
        fail "the ROM must remain outside the checkout: ${ROM_REAL_PATH}"
        ;;
esac

grep -Fq "${REFERENCE_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "Linux reference-build command is missing from ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${REFERENCE_HASH_COMMAND}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "Linux reference hash command is missing from ${REFERENCE_EVIDENCE_PATH}"
grep -Fq "${ROM_SHA1_EXPECTED}" "${REFERENCE_EVIDENCE_PATH}" ||
    fail "expected ROM SHA-1 is missing from ${REFERENCE_EVIDENCE_PATH}"

tracked_roms=$(git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64' '*.Z64' '*.N64')
[[ -z "${tracked_roms}" ]] || fail "a ROM is tracked by the checkout: ${tracked_roms}"
git -C "${PROJECT_ROOT}" check-ignore -q "${OUTPUT_DIR}" ||
    fail "native boot output is not ignored: ${OUTPUT_DIR}"

rom_size=$(byte_count "${ROM_REAL_PATH}")
[[ "${rom_size}" == "${ROM_SIZE_EXPECTED}" ]] ||
    fail "external ROM size mismatch: expected ${ROM_SIZE_EXPECTED}, got ${rom_size}"
rom_sha1=$(digest sha1 "${ROM_REAL_PATH}")
[[ "${rom_sha1}" == "${ROM_SHA1_EXPECTED}" ]] ||
    fail "external ROM SHA-1 mismatch: expected ${ROM_SHA1_EXPECTED}, got ${rom_sha1}"

log "external_rom=${ROM_PATH}"
log "external_rom_real_path=${ROM_REAL_PATH}"
log "external_rom_size=${rom_size}"
log "external_rom_sha1=${rom_sha1}"
log "linux_reference_evidence=${REFERENCE_EVIDENCE_PATH}"
log "linux_reference_command=${REFERENCE_COMMAND}"
log "linux_reference_hash_command=${REFERENCE_HASH_COMMAND}"
log "output_dir=${OUTPUT_DIR}"
log "rom_copied_into_checkout=false"
log "rom_copied_into_bundle=false"
log "private_payloads_copied_into_checkout=false"
log "private_payloads_copied_into_bundle=false"

# name|group|offset|size|compressed|source-row|kind|handle|source-sha1|source-sha256|decoded-size|decoded-sha1|decoded-sha256|flags
# The rows are the canonical US file-list ranges.  The gunbarrel background is
# included as its own exact row because it is used by title.c's barrel DL.
ASSETS=(
    'rarewarelogo|title|2745696|26608|0|2745696,26608,assets/rarewarelogo.bin,0,0|background|1|3293ec20258ebded49705e8194f1ebd28348de1c|90a5c04ed8461d21e8a766fb01673574b0484604a0284c65cab5527172b2decd|26608|3293ec20258ebded49705e8194f1ebd28348de1c|90a5c04ed8461d21e8a766fb01673574b0484604a0284c65cab5527172b2decd|BOOT_REQUIRED'
    'gunbarrel-background|title|2772304|107904|0|2772304,107904,assets/ge007.u.2A4D50.usedby7F008DE4.bin,0,1|background|2|2aed7980348475d247ffb778454ecb7236419536|b0704f2db5c0fc820050317a2848bba93b95dec4d37f6c1e040ffadb2bad8cf5|107904|2aed7980348475d247ffb778454ecb7236419536|b0704f2db5c0fc820050317a2848bba93b95dec4d37f6c1e040ffadb2bad8cf5|BOOT_REQUIRED'
    'goldeneyelogo|title|8262192|3760|1|8262192,3760,assets/obseg/prop/PgoldeneyelogoZ.bin,1,1|model|3|9fb0375864a5d8555fce005edeb94b1afca1cb5c|7d114c2d43b397a4a65ff8063ca2513bae8112514a4b17982f6ce2ca4eab9628|11248|1cbe4247a8b32892c337740f949ef1a10ac09df7|522959fd25a0d98bf70536b3b950eb230d817df3c1328f868b95e24a11850cad|BOOT_REQUIRED'
    'legalpage|title|8314032|4032|1|8314032,4032,assets/obseg/prop/PlegalpageZ.bin,1,1|model|4|9c79176d95c299a85c52bec9ad503981a287d505|035f5ecc61d3f320c3b1783fd304e58be4e8e759e4e7cc4e3fe6e9d576e06432|9232|b3e66bda241757cd916e7b51718ea9c11dc43f7c|80c1e51d0e0390d8a1a74e0cad88636c4bc85378defa94bed23b23d8b71bc25b|BOOT_REQUIRED'
    'nintendologo|title|8348000|10976|1|8348000,10976,assets/obseg/prop/PnintendologoZ.bin,1,1|model|5|ec321b57e92cfbbe6b9b51af518dacfc2d10689d|383868f7218e35f1c0868d48471b27cc1bc793d7b58ab1461a7fe5d0667dac77|31632|734df3758c69bef2c2fb3343546a6ee7ef7741ca|9748db560de2a949e173970f46d52d1831a791eb7bd3ac6d8bbfdba5cf1c514e|BOOT_REQUIRED'
    'walletbond|title|8526992|5552|1|8526992,5552,assets/obseg/prop/PwalletbondZ.bin,1,1|model|6|0df8c5ff12a9eb4dc503864a471a0855804c2406|c045cd4672d44ca1330a42a1a981a7b532baf2730265d9983ac24f62bff609f8|26384|1ae4cf5730961ca796b88f5be638133030cd790a|b66d911497d678da5b9aac2ea0b30b80fd09c9aa3ad6bf36d7e48878eec25156|BOOT_REQUIRED'
    'headbrosnansuit|title|7455952|3456|1|7455952,3456,assets/obseg/chr/CheadbrosnansuitZ.bin,1,1|model|7|42b8363ed449305c702d4d7fe68456b48f221865|fa5a6b4b881dc58bb938a7e6629ce02c17d9f6d15d0cb45da636755ab8a1f999|8368|9dc5e9304420c2342ba3b36fd6d508fe6c098222|aa78182e495c21ec498c2b5ec9278c8f5152747516f00f2d4eb4c2f4ff430623|BOOT_REQUIRED'
    'suitbond|title|7689936|11664|1|7689936,11664,assets/obseg/chr/CsuitbondZ.bin,1,1|model|8|39f0bffbdb89bfc9c442540634200cac380bda10|4bde0ddc19c5676b825dfd25016c0cad4ba6f57e6c21b869ddcc9a1a620e468e|28512|01847ac5441390e440671dcfdd3f41959f590bb2|521bc97bbdd7787fa74f2fda73bc2addb7732810de6301d74c55a1be7c8a7afa|BOOT_REQUIRED'
    'chrwppk|title|8189712|576|1|8189712,576,assets/obseg/prop/PchrwppkZ.bin,1,1|model|9|4154511f0038c88848a57ceab9aeb8e8f8767877|efb41ede0bc8ffab63ebca0dbbe26747ae01a634690b9451ccd099668143e533|1360|702eaceff93175af71c16e38db1a1f58e0173e07|8267298c98213d39011d8a29738cba594b93a96b87e1e56665058109affb3c8e|BOOT_REQUIRED'
    'LtitleE|title|9396000|2752|1|9396000,2752,assets/obseg/text/LtitleE,1,0|text|10|bb2ec8fd9ac65d151e2c69e3d585e1729180e969|d091dc32b56956a1445406df837fdcffd82ee45aedcf1d54b2ec6c1a6d9f2580|5024|363f3404b82ae973c85e346cd5d76e58403b10de|941cad932f414b9d3d86e3dc542c549f6c6c0de0725c4eeb4832be8496b3b4f1|BOOT_REQUIRED'
    'Mintro_eye|audio|4299660|2222|1|4299660,2222,assets/music/Mintro_eye.bin,1,1|music|11|54ffbb06555158145ba3e29f7419a9212368ad8e|218480903332acb81a5fa7a20c6e38794a774652fb3c1bfa7b7a39da32b6adbe|3826|fbab64a6ed67d61eb31ea7b8336e28f91bdb4991|5fd05f37ec52abdfc2d78566ea01942e81b0e443e15e8233a72261c2358e0385|BOOT_REQUIRED'
    'Mfolders|audio|4358444|994|1|4358444,994,assets/music/Mfolders.bin,1,1|music|12|8645efa72f7ba3b717993a37e88b74551fd9c79d|56ee0f36981e577038b934cf7d243f9c0be83c58fd82db5e059ea9b36cd2542c|1496|3ae2d018eaffc2c27b89e8e8a47d353265ef26f7|016ee22ed93b36a02eab84805c732cebc9afdb8d2eabf5502b4744ca40f29de8|BOOT_REQUIRED'
    'Mnint_rare_logo|audio|4395214|1074|1|4395214,1074,assets/music/Mnint_rare_logo.bin,1,1|music|13|9b241203bf607ae72ec8435abd4cb16a9b7ec21c|a7f342e38b282db90486d23255569313c064090acd6c599f394970f916800045|1498|201c9f3415d9f7ef289abf95c3c512c38df1371d|4afb1678f1e78b09189fb78ac2dab8df0f166bbe43f5a57b59906a86db02ea88|BOOT_REQUIRED'
    'instruments.ctl|audio|3884112|17312|0|3884112,17312,assets/music/instruments.ctl,0,1|instrument_ctl|14|0382bb85770269a2bae52065ae52335d27403bb2|6673abfeeec570e71ba28018189298ba0bfa1f0be190de1068e7b3c99f56ba4a|17312|0382bb85770269a2bae52065ae52335d27403bb2|6673abfeeec570e71ba28018189298ba0bfa1f0be190de1068e7b3c99f56ba4a|BOOT_REQUIRED'
    'instruments.tbl|audio|3901424|397216|0|3901424,397216,assets/music/instruments.tbl,0,1|instrument_tbl|15|3dcbc8919f930a268a9d6fae9fed04147d42ee1b|1c85fbfa162f4b1245afd2f5dc70322776a7d5003b8b0cc9549110942489befd|397216|3dcbc8919f930a268a9d6fae9fed04147d42ee1b|1c85fbfa162f4b1245afd2f5dc70322776a7d5003b8b0cc9549110942489befd|BOOT_REQUIRED'
    'sfx.ctl|audio|3063264|23488|0|3063264,23488,assets/music/sfx.ctl,0,1|sfx_ctl|16|80037e6af46618f9a75e13ddd623f716fa3a1565|9da8bd0484ea18807924672fbf49ee2ef26631e37ae5b993be6f6fc4f9bd2f77|23488|80037e6af46618f9a75e13ddd623f716fa3a1565|9da8bd0484ea18807924672fbf49ee2ef26631e37ae5b993be6f6fc4f9bd2f77|BOOT_REQUIRED'
    'sfx.tbl|audio|3086752|797360|0|3086752,797360,assets/music/sfx.tbl,0,1|sfx_tbl|17|9750509b073bd15089e63c518d2f338001b5fe1e|7918a56547e86891f45a46588db15eb7cc6896ccd99a4045a5fe2470a06baa12|797360|9750509b073bd15089e63c518d2f338001b5fe1e|7918a56547e86891f45a46588db15eb7cc6896ccd99a4045a5fe2470a06baa12|BOOT_REQUIRED'
)

ASSETS+=(
    'ramrom_Dam_1|ramrom|2880208|20992|0|2880208,20992,assets/ramrom/ramrom_Dam_1.bin,0,1|ramrom|101|b2ce7dded37c493649e77002551fc82367cc64f4|af2e06685a349e0ed84288f6ac33fb76e2f8588b3acd2eedaed7485f5c1228ac|20992|b2ce7dded37c493649e77002551fc82367cc64f4|af2e06685a349e0ed84288f6ac33fb76e2f8588b3acd2eedaed7485f5c1228ac|ATTRACT_REQUIRED'
    'ramrom_Dam_2|ramrom|2901200|8144|0|2901200,8144,assets/ramrom/ramrom_Dam_2.bin,0,1|ramrom|102|4b71eb8897658cb8b00399040d3b2b7b6fa52362|adf5cedac3b111ba7e9ff0f193f543fee027d874a7ffc6f9f54f3bc80fa646fe|8144|4b71eb8897658cb8b00399040d3b2b7b6fa52362|adf5cedac3b111ba7e9ff0f193f543fee027d874a7ffc6f9f54f3bc80fa646fe|ATTRACT_REQUIRED'
    'ramrom_Facility_1|ramrom|2909344|6832|0|2909344,6832,assets/ramrom/ramrom_Facility_1.bin,0,1|ramrom|103|08397903dfc616f29f6d70dcf7121c81dd1cf212|3180cfd486a77777b74c87df337adaebbc2f2ff38e2cebd99b248080ba9bdd63|6832|08397903dfc616f29f6d70dcf7121c81dd1cf212|3180cfd486a77777b74c87df337adaebbc2f2ff38e2cebd99b248080ba9bdd63|ATTRACT_REQUIRED'
    'ramrom_Facility_2|ramrom|2916176|9184|0|2916176,9184,assets/ramrom/ramrom_Facility_2.bin,0,1|ramrom|104|48158ec0000365b6e145716e7bd6b73532037652|4339b4158ad6d58d9422e88684349209f1cc50638e8bd9d0d55a9e9f19c3b59f|9184|48158ec0000365b6e145716e7bd6b73532037652|4339b4158ad6d58d9422e88684349209f1cc50638e8bd9d0d55a9e9f19c3b59f|ATTRACT_REQUIRED'
    'ramrom_Facility_3|ramrom|2925360|7280|0|2925360,7280,assets/ramrom/ramrom_Facility_3.bin,0,1|ramrom|105|f741286ce448dd3dc9bcc636dd97a507646d6270|2b9cb26d368b9bccad4f2a17638c8624cc36fc87759152c000c36af09639f3a1|7280|f741286ce448dd3dc9bcc636dd97a507646d6270|2b9cb26d368b9bccad4f2a17638c8624cc36fc87759152c000c36af09639f3a1|ATTRACT_REQUIRED'
    'ramrom_Runway_1|ramrom|2932640|10064|0|2932640,10064,assets/ramrom/ramrom_Runway_1.bin,0,1|ramrom|106|0bc9fd1bb8b81c74fa942791c4c9a35ef431eecf|726d6c77b509523ab34d8fcf859b0ac8ade2552c785552b1c677adb15ffbbb32|10064|0bc9fd1bb8b81c74fa942791c4c9a35ef431eecf|726d6c77b509523ab34d8fcf859b0ac8ade2552c785552b1c677adb15ffbbb32|ATTRACT_REQUIRED'
    'ramrom_Runway_2|ramrom|2942704|10512|0|2942704,10512,assets/ramrom/ramrom_Runway_2.bin,0,1|ramrom|107|68e16b9794b28f9effdb07faa4539efea1d4ccb0|4dbd52a811f4c7667298dd16c3ec0a1620b22e258968f157d0fb01163db385d0|10512|68e16b9794b28f9effdb07faa4539efea1d4ccb0|4dbd52a811f4c7667298dd16c3ec0a1620b22e258968f157d0fb01163db385d0|ATTRACT_REQUIRED'
    'ramrom_BunkerI_1|ramrom|2953216|13200|0|2953216,13200,assets/ramrom/ramrom_BunkerI_1.bin,0,1|ramrom|108|210bd1e3c70a39d25676c7037109d31c5d0f25a2|e0b409fa6d2e65f1d196f82ba62949b146196b63d3dd728a9687043a6a1e8a22|13200|210bd1e3c70a39d25676c7037109d31c5d0f25a2|e0b409fa6d2e65f1d196f82ba62949b146196b63d3dd728a9687043a6a1e8a22|ATTRACT_REQUIRED'
    'ramrom_BunkerI_2|ramrom|2966416|21120|0|2966416,21120,assets/ramrom/ramrom_BunkerI_2.bin,0,1|ramrom|109|393428d1092193a004d250b0adc851befe528106|4ed0ec8f2610a7e4c308eab80eb853c85bd7e2917ad15ee8212809b46d525fcf|21120|393428d1092193a004d250b0adc851befe528106|4ed0ec8f2610a7e4c308eab80eb853c85bd7e2917ad15ee8212809b46d525fcf|ATTRACT_REQUIRED'
    'ramrom_Silo_1|ramrom|2987536|8592|0|2987536,8592,assets/ramrom/ramrom_Silo_1.bin,0,1|ramrom|110|09403c68ef76519fa7e4b3c79ccfbff8a18cad8d|d011b7aa88cb10cbed8130873e000708e2071d4a25c8780dd928a28362a2ebb4|8592|09403c68ef76519fa7e4b3c79ccfbff8a18cad8d|d011b7aa88cb10cbed8130873e000708e2071d4a25c8780dd928a28362a2ebb4|ATTRACT_REQUIRED'
    'ramrom_Silo_2|ramrom|2996128|8144|0|2996128,8144,assets/ramrom/ramrom_Silo_2.bin,0,1|ramrom|111|12b34d97a5aa2061bdf3af6d7546bbb23079eacf|8310f99672edbcc7f9dba022ac45cfdcc06aaadbdf99f693e780fd550ac8b680|8144|12b34d97a5aa2061bdf3af6d7546bbb23079eacf|8310f99672edbcc7f9dba022ac45cfdcc06aaadbdf99f693e780fd550ac8b680|ATTRACT_REQUIRED'
    'ramrom_Frigate_1|ramrom|3004272|6576|0|3004272,6576,assets/ramrom/ramrom_Frigate_1.bin,0,1|ramrom|112|dd6f5df2093d39a80a042ea305721f6e12dbe723|1016de77a86526a9d6aa08813c77b0d1b26735c6266a546f8a7124a6e878a060|6576|dd6f5df2093d39a80a042ea305721f6e12dbe723|1016de77a86526a9d6aa08813c77b0d1b26735c6266a546f8a7124a6e878a060|ATTRACT_REQUIRED'
    'ramrom_Frigate_2|ramrom|3010848|13536|0|3010848,13536,assets/ramrom/ramrom_Frigate_2.bin,0,1|ramrom|113|1ae6fbb14b3e9010444da185d8c32cc152a31508|1110c466021e03923375b7e785a18af496f383fc632630d8f3bfccbdba1a1802|13536|1ae6fbb14b3e9010444da185d8c32cc152a31508|1110c466021e03923375b7e785a18af496f383fc632630d8f3bfccbdba1a1802|ATTRACT_REQUIRED'
    'ramrom_Train|ramrom|3024384|15856|0|3024384,15856,assets/ramrom/ramrom_Train.bin,0,1|ramrom|114|574b357832d543bfaa9e4bd7a790cb1b2f682eaf|16b7bb36dd175b2a72ec3e0b5d314fdd07faef40d6410e5f2afd77c644d3b4c8|15856|574b357832d543bfaa9e4bd7a790cb1b2f682eaf|16b7bb36dd175b2a72ec3e0b5d314fdd07faef40d6410e5f2afd77c644d3b4c8|ATTRACT_REQUIRED'
)

asset_index=0
for entry in "${ASSETS[@]}"; do
    IFS='|' read -r name group offset size compressed source_row kind handle \
        expected_source_sha1 expected_source_sha256 decoded_size \
        expected_decoded_sha1 expected_decoded_sha256 flags <<< "${entry}"

    require_exact_line "${source_row}" "${FILELIST_PATH}"

    case "${group}" in
        title) group_dir="${TITLE_DIR}" ;;
        audio) group_dir="${AUDIO_DIR}" ;;
        ramrom) group_dir="${RAMROM_DIR}" ;;
        *) fail "unknown asset group: ${group}" ;;
    esac

    if [[ "${compressed}" == 1 ]]; then
        raw_path="${group_dir}/${name}.rz"
        decoded_path="${group_dir}/${name}.bin"
    elif [[ "${compressed}" == 0 ]]; then
        raw_path=$(direct_asset_path "${group_dir}" "${name}")
        decoded_path="${raw_path}"
    else
        fail "invalid compression flag for ${name}: ${compressed}"
    fi

    log "extracting=${name} group=${group} offset=${offset} size=${size} compressed=${compressed}"
    if ! dd if="${ROM_REAL_PATH}" of="${raw_path}" bs=1 skip="${offset}" count="${size}" \
        >>"${LOG_PATH}" 2>&1; then
        fail "failed to extract ${name} from the external ROM"
    fi

    actual_size=$(byte_count "${raw_path}")
    [[ "${actual_size}" == "${size}" ]] ||
        fail "${name} source size mismatch: expected ${size}, got ${actual_size}"
    actual_source_sha1=$(digest sha1 "${raw_path}")
    [[ "${actual_source_sha1}" == "${expected_source_sha1}" ]] ||
        fail "${name} source SHA-1 mismatch: expected ${expected_source_sha1}, got ${actual_source_sha1}"
    actual_source_sha256=$(digest sha256 "${raw_path}")
    [[ "${actual_source_sha256}" == "${expected_source_sha256}" ]] ||
        fail "${name} source SHA-256 mismatch: expected ${expected_source_sha256}, got ${actual_source_sha256}"

    if [[ "${compressed}" == 1 ]]; then
        if ! GZ=gzip "${INFLATE_PATH}" "${raw_path}" "${decoded_path}" \
            >>"${LOG_PATH}" 2>&1; then
            fail "1172 decompression failed for ${name}"
        fi
    fi

    actual_decoded_size=$(byte_count "${decoded_path}")
    [[ "${actual_decoded_size}" == "${decoded_size}" ]] ||
        fail "${name} decoded size mismatch: expected ${decoded_size}, got ${actual_decoded_size}"
    actual_decoded_sha1=$(digest sha1 "${decoded_path}")
    [[ "${actual_decoded_sha1}" == "${expected_decoded_sha1}" ]] ||
        fail "${name} decoded SHA-1 mismatch: expected ${expected_decoded_sha1}, got ${actual_decoded_sha1}"
    actual_decoded_sha256=$(digest sha256 "${decoded_path}")
    [[ "${actual_decoded_sha256}" == "${expected_decoded_sha256}" ]] ||
        fail "${name} decoded SHA-256 mismatch: expected ${expected_decoded_sha256}, got ${actual_decoded_sha256}"

    asset_index=$((asset_index + 1))
    log "asset_pass=${name} source_sha256=${actual_source_sha256} decoded_sha256=${actual_decoded_sha256}"
done

# Lower the bounded source-derived title geometry packet after the ROM-backed
# payloads have passed their hash guards.  This step never reads the ROM: it
# consumes the generated Model.c listings already present in the checkout and
# writes only ignored .gepk packets beside the prepared title assets.  Older
# checkouts that do not carry those generated listings remain runnable with
# the explicit visual placeholder and record the reason in the manifest.
TITLE_GEOMETRY_SCRIPT="${PROJECT_ROOT}/scripts/prepare_native_title_geometry.py"
TITLE_GEOMETRY_REPORT="${TITLE_DIR}/native-title-geometry-report.txt"
TITLE_GEOMETRY_STATUS="SKIP"
TITLE_GEOMETRY_MISSING=()
for geometry_source in \
    "${PROJECT_ROOT}/assets/obseg/prop/legalpage/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/nintendologo/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/goldeneyelogo/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/walletbond/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/chr/headbrosnansuit/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/chr/suitbond/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/chrwppk/Model.c"; do
    if [[ ! -f "${geometry_source}" ]]; then
        TITLE_GEOMETRY_MISSING+=("${geometry_source}")
    fi
done
if [[ ${#TITLE_GEOMETRY_MISSING[@]} -eq 0 ]]; then
    if ! python3 "${TITLE_GEOMETRY_SCRIPT}" \
        --project-root "${PROJECT_ROOT}" \
        --output-root "${TITLE_DIR}" \
        --report "${TITLE_GEOMETRY_REPORT}" >>"${LOG_PATH}" 2>&1; then
        fail "source-derived title geometry extraction failed"
    fi
    TITLE_GEOMETRY_STATUS="PASS"
    log "title_geometry_status=PASS"
else
    log "title_geometry_status=SKIP"
    log "title_geometry_reason=generated Model.c listings unavailable"
    for missing_geometry_source in "${TITLE_GEOMETRY_MISSING[@]}"; do
        log "title_geometry_missing=${missing_geometry_source}"
    done
fi

# Lower the additive GETU source UV/material corner stream for the three
# branded title models.  GETU preserves signed Vertex.s/t, the active
# source-local texture handle, and a deterministic source-command hash while
# leaving GETP and all frozen V1--V4 artifacts unchanged.  Preparation reads
# generated Model.c listings only and never opens the external ROM.
TITLE_UV_SCRIPT="${PROJECT_ROOT}/scripts/prepare_native_title_uv.py"
TITLE_UV_REPORT="${TITLE_DIR}/native-title-uv-report.txt"
TITLE_UV_STATUS="SKIP"
TITLE_UV_MISSING=()
for uv_source in \
    "${PROJECT_ROOT}/assets/obseg/prop/legalpage/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/nintendologo/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/goldeneyelogo/Model.c"; do
    if [[ ! -f "${uv_source}" ]]; then
        TITLE_UV_MISSING+=("${uv_source}")
    fi
done
if [[ ${#TITLE_UV_MISSING[@]} -eq 0 && -f "${TITLE_UV_SCRIPT}" ]]; then
    if ! python3 "${TITLE_UV_SCRIPT}" \
        --project-root "${PROJECT_ROOT}" \
        --output-root "${TITLE_DIR}" \
        --report "${TITLE_UV_REPORT}" >>"${LOG_PATH}" 2>&1; then
        fail "source-derived title UV preparation failed"
    fi
    TITLE_UV_STATUS="PASS"
    log "title_uv_status=PASS"
else
    log "title_uv_status=SKIP"
    log "title_uv_reason=branded Model.c listings unavailable"
    for missing_uv_source in "${TITLE_UV_MISSING[@]}"; do
        log "title_uv_missing=${missing_uv_source}"
    done
fi

# Emit the additive M7 value-only frontend node packets from generated source
# listings. This never reads the ROM and leaves the existing GETP packets and
# hashes untouched; missing listings fail closed for this optional lane while
# the bounded title placeholder remains runnable.
TITLE_NODES_SCRIPT="${PROJECT_ROOT}/scripts/prepare_native_title_nodes.py"
TITLE_NODES_REPORT="${TITLE_DIR}/native-title-node-report.txt"
TITLE_NODES_MISSING=()
for node_source in \
    "${PROJECT_ROOT}/assets/obseg/prop/legalpage/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/nintendologo/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/goldeneyelogo/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/walletbond/Model.c"; do
    if [[ ! -f "${node_source}" ]]; then
        TITLE_NODES_MISSING+=("${node_source}")
    fi
done
if [[ ${#TITLE_NODES_MISSING[@]} -eq 0 ]]; then
    if ! python3 "${TITLE_NODES_SCRIPT}" \
        --project-root "${PROJECT_ROOT}" \
        --output-root "${TITLE_DIR}" \
        --report "${TITLE_NODES_REPORT}" >>"${LOG_PATH}" 2>&1; then
        fail "source-derived title node extraction failed"
    fi
    log "title_node_status=PASS"
else
    log "title_node_status=SKIP"
    for missing_node_source in "${TITLE_NODES_MISSING[@]}"; do
        log "title_node_missing=${missing_node_source}"
    done
fi

TITLE_TEXT_SCRIPT="${PROJECT_ROOT}/scripts/prepare_native_title_text.py"
TITLE_TEXT_REPORT="${TITLE_DIR}/native-title-text-report.txt"
TITLE_TEXT_STATUS="SKIP"
if [[ -f "${PROJECT_ROOT}/assets/font/fontZurichBold.c" \
    && -f "${PROJECT_ROOT}/assets/obseg/text/LtitleE.c" ]]; then
    if ! python3 "${TITLE_TEXT_SCRIPT}" \
        --project-root "${PROJECT_ROOT}" \
        --output-root "${TITLE_DIR}" \
        --report "${TITLE_TEXT_REPORT}" >>"${LOG_PATH}" 2>&1; then
        fail "source-derived title text preparation failed"
    fi
    TITLE_TEXT_STATUS="PASS"
    log "title_text_status=PASS"
else
    log "title_text_status=SKIP"
    log "title_text_reason=Zurich or LtitleE source listing unavailable"
fi

# Lower the guarded source-derived frontend icon rows.  The packet contains
# decoded RGBA8 pixels and fixed-width provenance only; tex2png reads the
# checked-in PD streams and never opens the external ROM at runtime.
TITLE_ICON_SCRIPT="${PROJECT_ROOT}/scripts/prepare_native_title_icons.py"
TITLE_ICON_REPORT="${TITLE_DIR}/native-title-icons-report.txt"
TITLE_ICON_STATUS="SKIP"
if [[ -x "${TITLE_ICON_SCRIPT}" || -f "${TITLE_ICON_SCRIPT}" ]]; then
    if ! python3 "${TITLE_ICON_SCRIPT}" \
        --project-root "${PROJECT_ROOT}" \
        --output-root "${TITLE_DIR}" \
        --report "${TITLE_ICON_REPORT}" >>"${LOG_PATH}" 2>&1; then
        fail "source-derived title icon preparation failed"
    fi
    TITLE_ICON_STATUS="PASS"
    log "title_icon_status=PASS"
else
    log "title_icon_status=SKIP"
    log "title_icon_reason=title icon preparation script unavailable"
fi

# Lower the additive GETT source texture/material rows after the guarded model
# blobs and frontend image streams are present.  Direct model rows are decoded
# from the prepared .bin payloads at source-local offsets; walletbond rows are
# decoded from checked-in PD image streams through tex2png.  The packet writer
# never opens the external ROM and leaves GETP/V1--V4 artifacts untouched.
TITLE_TEXTURE_SCRIPT="${PROJECT_ROOT}/scripts/prepare_native_title_textures.py"
TITLE_TEXTURE_REPORT="${TITLE_DIR}/native-title-texture-report.txt"
TITLE_TEXTURE_STATUS="SKIP"
TITLE_TEXTURE_MISSING=()
for texture_source in \
    "${PROJECT_ROOT}/assets/obseg/prop/legalpage/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/nintendologo/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/goldeneyelogo/Model.c" \
    "${PROJECT_ROOT}/assets/obseg/prop/walletbond/Model.c" \
    "${TITLE_DIR}/legalpage.bin" \
    "${TITLE_DIR}/nintendologo.bin" \
    "${TITLE_DIR}/goldeneyelogo.bin"; do
    if [[ ! -f "${texture_source}" ]]; then
        TITLE_TEXTURE_MISSING+=("${texture_source}")
    fi
done
if [[ ${#TITLE_TEXTURE_MISSING[@]} -eq 0 && -f "${TITLE_TEXTURE_SCRIPT}" ]]; then
    if ! python3 "${TITLE_TEXTURE_SCRIPT}" \
        --project-root "${PROJECT_ROOT}" \
        --output-root "${TITLE_DIR}" \
        --report "${TITLE_TEXTURE_REPORT}" >>"${LOG_PATH}" 2>&1; then
        fail "source-derived title texture preparation failed"
    fi
    TITLE_TEXTURE_STATUS="PASS"
    log "title_texture_status=PASS"
else
    log "title_texture_status=SKIP"
    log "title_texture_reason=generated model/blob listings unavailable"
    for missing_texture_source in "${TITLE_TEXTURE_MISSING[@]}"; do
        log "title_texture_missing=${missing_texture_source}"
    done
fi

# The fidelity-recovery catalog is additive to the earlier bounded GET*
# packets. It preserves the complete source model/display-list/material input
# and writes only to an ignored build/native root. Runtime still never opens
# the external ROM.
if [[ ! -x "${SOURCE_FRONTEND_V6_SCRIPT}" ]]; then
    fail "source frontend V6 preparation script is unavailable"
fi
# The old b924 generation is retained as immutable evidence.  If it exists in
# this checkout, fail before preparation rather than allowing a future path
# regression to overwrite or silently replace it.
if [[ -e "${PRESERVED_LEGACY_SOURCE_FRONTEND_V6_PACKET}" ]]; then
    [[ -f "${PRESERVED_LEGACY_SOURCE_FRONTEND_V6_PACKET}" ]] ||
        fail "preserved legacy source catalog packet is not a regular file"
    [[ "$(digest sha256 "${PRESERVED_LEGACY_SOURCE_FRONTEND_V6_PACKET}")" == "${PRESERVED_LEGACY_SOURCE_FRONTEND_V6_PACKET_SHA256}" ]] ||
        fail "preserved legacy b924 source catalog packet changed"
fi
if ! "${SOURCE_FRONTEND_V6_SCRIPT}" \
    --project-root "${PROJECT_ROOT}" \
    --rom "${ROM_REAL_PATH}" \
    --output-root "${SOURCE_FRONTEND_V6_DIR}" >>"${LOG_PATH}" 2>&1; then
    fail "source frontend V6 preparation failed"
fi
if [[ ! -f "${SOURCE_FRONTEND_V6_REPORT}" ]] ||
   ! grep -Fqx 'status=PASS' "${SOURCE_FRONTEND_V6_REPORT}"; then
    fail "source frontend V6 report is missing or incomplete"
fi
log "source_frontend_v6_status=PASS"

if find "${OUTPUT_DIR}" -type f \( -name '*.z64' -o -name '*.n64' -o -name '*.Z64' -o -name '*.N64' \) \
    -print -quit | grep -q .; then
    fail "a ROM-like file appeared in the native boot output"
fi
if find "${OUTPUT_DIR}" -type d -name '*.app' -print -quit | grep -q .; then
    fail "an application bundle appeared in the native boot output"
fi

MANIFEST_TMP="${MANIFEST_PATH}.tmp.$$"
trap 'rm -f "${MANIFEST_TMP}"' EXIT
{
    printf '%s\n' 'manifest_version=1'
    printf '%s\n' 'goal=native-boot-menu-attract-120'
    printf 'asset_count=%s\n' "${asset_index}"
    printf 'external_rom_path=%s\n' "${ROM_PATH}"
    printf 'external_rom_real_path=%s\n' "${ROM_REAL_PATH}"
    printf 'external_rom_size=%s\n' "${rom_size}"
    printf 'external_rom_sha1=%s\n' "${rom_sha1}"
    printf 'linux_reference_evidence=%s\n' "${REFERENCE_EVIDENCE_PATH}"
    printf 'linux_reference_command=%s\n' "${REFERENCE_COMMAND}"
    printf 'linux_reference_hash_command=%s\n' "${REFERENCE_HASH_COMMAND}"
    printf 'output_dir=%s\n' "${OUTPUT_DIR}"
    printf '%s\n' 'rom_copied_into_checkout=false'
    printf '%s\n' 'rom_copied_into_bundle=false'
    printf '%s\n' 'private_payloads_copied_into_checkout=false'
    printf '%s\n' 'private_payloads_copied_into_bundle=false'
    printf 'title_geometry_status=%s\n' "${TITLE_GEOMETRY_STATUS}"
    printf '%s\n' 'title_geometry_runtime_rom_access=false'
    printf '%s\n' 'title_geometry_visual_parity=not-claimed'
    if [[ -f "${TITLE_GEOMETRY_REPORT}" ]]; then
        while IFS= read -r geometry_line; do
            [[ -n "${geometry_line}" ]] || continue
            printf 'title_geometry_%s\n' "${geometry_line}"
        done < "${TITLE_GEOMETRY_REPORT}"
    fi
    printf 'title_uv_status=%s\n' "${TITLE_UV_STATUS}"
    printf '%s\n' 'title_uv_runtime_rom_access=false'
    printf '%s\n' 'title_uv_visual_parity=not-claimed'
    if [[ -f "${TITLE_UV_REPORT}" ]]; then
        while IFS= read -r uv_line; do
            [[ -n "${uv_line}" ]] || continue
            printf 'title_uv_%s\n' "${uv_line}"
        done < "${TITLE_UV_REPORT}"
    fi
    printf 'title_text_status=%s\n' "${TITLE_TEXT_STATUS}"
    printf '%s\n' 'title_text_runtime_rom_access=false'
    printf '%s\n' 'title_text_visual_parity=not-claimed'
    if [[ -f "${TITLE_TEXT_REPORT}" ]]; then
        while IFS= read -r text_line; do
            [[ -n "${text_line}" ]] || continue
            printf 'title_text_%s\n' "${text_line}"
        done < "${TITLE_TEXT_REPORT}"
    fi
    printf 'title_icon_status=%s\n' "${TITLE_ICON_STATUS}"
    printf '%s\n' 'title_icon_runtime_rom_access=false'
    printf '%s\n' 'title_icon_visual_parity=not-claimed'
    if [[ -f "${TITLE_ICON_REPORT}" ]]; then
        while IFS= read -r icon_line; do
            [[ -n "${icon_line}" ]] || continue
            printf 'title_icon_%s\n' "${icon_line}"
        done < "${TITLE_ICON_REPORT}"
    fi
    printf 'title_texture_status=%s\n' "${TITLE_TEXTURE_STATUS}"
    printf '%s\n' 'title_texture_runtime_rom_access=false'
    printf '%s\n' 'title_texture_visual_parity=not-claimed'
    if [[ -f "${TITLE_TEXTURE_REPORT}" ]]; then
        while IFS= read -r texture_line; do
            [[ -n "${texture_line}" ]] || continue
            printf 'title_texture_%s\n' "${texture_line}"
        done < "${TITLE_TEXTURE_REPORT}"
    fi
    printf '%s\n' 'source_frontend_v6_status=PASS'
    printf '%s\n' 'source_frontend_v6_runtime_rom_access=false'
    printf '%s\n' 'source_frontend_v6_visual_parity=not-claimed'
    while IFS= read -r source_frontend_line; do
        [[ -n "${source_frontend_line}" ]] || continue
        printf 'source_frontend_v6_%s\n' "${source_frontend_line}"
    done < "${SOURCE_FRONTEND_V6_REPORT}"
    for entry in "${ASSETS[@]}"; do
        IFS='|' read -r name group offset size compressed source_row kind handle \
            expected_source_sha1 expected_source_sha256 decoded_size \
            expected_decoded_sha1 expected_decoded_sha256 flags <<< "${entry}"
        if [[ "${compressed}" == 1 ]]; then
            raw_path="${group}/${name}.rz"
            decoded_path="${group}/${name}.bin"
        else
            raw_path=$(direct_asset_path "${group}" "${name}")
            decoded_path="${raw_path}"
        fi
        printf 'asset_%s_name=%s\n' "${handle}" "${name}"
        printf 'asset_%s_group=%s\n' "${handle}" "${group}"
        printf 'asset_%s_kind=%s\n' "${handle}" "${kind}"
        printf 'asset_%s_source_row=%s\n' "${handle}" "${source_row}"
        printf 'asset_%s_rom_offset=%s\n' "${handle}" "${offset}"
        printf 'asset_%s_source_size=%s\n' "${handle}" "${size}"
        printf 'asset_%s_source_sha1=%s\n' "${handle}" "${expected_source_sha1}"
        printf 'asset_%s_source_sha256=%s\n' "${handle}" "${expected_source_sha256}"
        printf 'asset_%s_decoded_size=%s\n' "${handle}" "${decoded_size}"
        printf 'asset_%s_decoded_sha1=%s\n' "${handle}" "${expected_decoded_sha1}"
        printf 'asset_%s_decoded_sha256=%s\n' "${handle}" "${expected_decoded_sha256}"
        printf 'asset_%s_compressed=%s\n' "${handle}" "${compressed}"
        printf 'asset_%s_flags=%s\n' "${handle}" "${flags}"
        if [[ "${compressed}" == 1 ]]; then
            printf 'asset_%s_flags_mask=0x07\n' "${handle}"
        else
            printf 'asset_%s_flags_mask=0x06\n' "${handle}"
        fi
        printf 'asset_%s_catalog_id=%s\n' "${handle}" "${handle}"
        printf 'asset_%s_raw_path=%s\n' "${handle}" "${raw_path}"
        printf 'asset_%s_decoded_path=%s\n' "${handle}" "${decoded_path}"
    done
    printf '%s\n' 'tracked_rom_guard=pass'
    printf '%s\n' 'reference_evidence_guard=pass'
    printf '%s\n' 'asset_hash_guard=pass'
    printf '%s\n' 'manifest_status=PASS'
} > "${MANIFEST_TMP}"
mv -f "${MANIFEST_TMP}" "${MANIFEST_PATH}"
trap - EXIT

log "manifest_path=${MANIFEST_PATH}"
log "asset_count=${asset_index}"
log "manifest_status=PASS"
