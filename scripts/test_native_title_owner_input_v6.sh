#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
OWNER="${ROOT}/native/host/native_title_owner.swift"
PAIRED_AUTHORITY="${ROOT}/native/host/goldeneye_original_paired_authority_v6.swift"
AUTHORITY="${ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift"
MAILBOX="${ROOT}/native/host/native_input_mailbox.swift"

grep -Fq 'physicalControllerCount' "${MAILBOX}"
grep -Fq 'fileModeHeld: sourceInput.fileModeHeld' "${OWNER}"
grep -Fq 'fileModePressed: sourceInput.fileModePressed' "${OWNER}"
grep -Fq 'fileModeReleased: sourceInput.fileModeReleased' "${OWNER}"
grep -Fq 'fileModeStickX: sourceInput.fileModeStickX' "${OWNER}"
grep -Fq 'fileModeStickY: sourceInput.fileModeStickY' "${OWNER}"
grep -Fq 'fileModeControllerCount: sourceInput.physicalControllerCount' "${OWNER}"
grep -Fq 'controllerCount: sourceInput.effectiveControllerCount' "${OWNER}"
grep -Fq 'private var sourceAuthority: GoldenEyeOriginalPairedAuthorityV6?' "${OWNER}"
grep -Fq 'original-paired-v6' "${OWNER}"
if grep -Fq 'private var sourceAuthority: GoldenEyeSourceFrontendAuthorityV6?' "${OWNER}"; then
    echo 'native title owner still owns standalone source authority' >&2
    exit 1
fi

SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
"${SWIFTC}" -frontend -parse -sdk "${SDKROOT}" \
    "${OWNER}" "${PAIRED_AUTHORITY}" "${AUTHORITY}" "${MAILBOX}"

echo 'native title owner physical/file-mode input handoff: PASS'
