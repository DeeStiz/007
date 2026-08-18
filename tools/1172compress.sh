#!/bin/bash

usage()
{
    echo "Rare 1172 compression script"
    echo "Usage: $0 input output" 1>&2;
    exit 1;
}

if [ -z "$1" ]; then
    usage
fi;

if [ -z "$2" ]; then
    usage
fi;

# input file to compress
INPUT_FILE="$1"
# output file result
OUTPUT_FILE="$2"
# gzip command.
GZ=${GZ:-'gzipsrc/gzip'}

# check for decomp gzip, then fall back to system
if [ ! -f "${GZ}" ]; then
    # maybe user specified shell variable but it's not resolved as a file
    if ! command -v "${GZ}" &> /dev/null
    then
        # nope, maybe we're in the root directory
        if [ ! -f 'tools/gzipsrc/gzip' ]; then
            # nope, fallback to system gzip
            echo "decomp gzip bin not found, falling back to system gzip"
            GZ="gzip"
            if ! command -v "${GZ}" &> /dev/null
            then
                echo "can not find system gzip"
                exit 2
            fi
        else
            GZ='tools/gzipsrc/gzip'
        fi
    fi
fi

# make sure input file exists
if [ ! -f "${INPUT_FILE}" ]; then
    echo "can not read input file"
    usage
fi

# create
echo -n -e \\x11\\x72 > "${OUTPUT_FILE}"

# The 1172 wrapper stores the gzip payload without its ten-byte header and
# eight-byte trailer.  GNU `head --bytes=-8` was used here historically, but
# that option is not available in the macOS toolchain.  Materialize the
# compressor output once, then use POSIX-style `dd` byte ranges so the exact
# payload is identical on Darwin and Linux.
TMP_COMPRESSED=$(mktemp "${TMPDIR:-/tmp}/goldeneye-1172compress.XXXXXX") || exit 1
cleanup() {
    rm -f "${TMP_COMPRESSED}"
}
trap cleanup EXIT HUP INT TERM

if ! $GZ --no-name --best < "${INPUT_FILE}" > "${TMP_COMPRESSED}"; then
    echo "compression failed for ${INPUT_FILE}" 1>&2
    exit 1
fi

COMPRESSED_SIZE=$(wc -c < "${TMP_COMPRESSED}")
PAYLOAD_SIZE=$((COMPRESSED_SIZE - 18))
if [ "${PAYLOAD_SIZE}" -lt 0 ]; then
    echo "compressed output is too short: ${COMPRESSED_SIZE} bytes" 1>&2
    exit 1
fi

dd if="${TMP_COMPRESSED}" bs=1 skip=10 count="${PAYLOAD_SIZE}" 2>/dev/null >> "${OUTPUT_FILE}"
