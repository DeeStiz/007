#!/bin/bash
MAPFILE="./build/"$2"/ge007."$2".map"
#this script is a hacky mess that can most definately be improved
#fixme as I will fail if vaddr of data gets moved!!!
# Parse the canonical symbols/section instead of relying on a fixed-width
# linker-map spelling.  Bash arithmetic accepts the hexadecimal values on both
# Darwin and Linux, while the old `printf 0x...` form does not on macOS.
DATASEG_START_HEX=$(awk '/__csegtempPos[[:space:]]*=/ { print $4; exit }' "${MAPFILE}")
DATASEG_LEN_HEX=$(awk '$1 == ".csegment" { print $3; exit }' "${MAPFILE}")
if [ -z "${DATASEG_START_HEX}" ] || [ -z "${DATASEG_LEN_HEX}" ]; then
    echo "could not locate csegment bounds in ${MAPFILE}" 1>&2
    exit 1
fi
DATASEG_START=$((DATASEG_START_HEX))
DATASEG_LEN=$((DATASEG_LEN_HEX))

#build/rebuild aaa_rip
[ ! -x tools/aaa_rip/aaa_rip ] && make -C tools/aaa_rip

echo "patching $1"
echo "extract data segment"
[ -x tools/aaa_rip/aaa_rip ] && tools/aaa_rip/aaa_rip $1 build/$2/data_seg ${DATASEG_START} ${DATASEG_LEN} || dd skip=${DATASEG_START} count=${DATASEG_LEN} if=$1 of=build/$2/data_seg bs=1

echo "truncate $1 to 0x$(printf "%x\n" ${DATASEG_START})"
dd if="$1" of="$1.tmp" bs=1 count="${DATASEG_START}" 2>/dev/null

echo "compress data segment"
tools/1172compress.sh build/$2/data_seg build/$2/data_seg.rz


echo "inject data segment"
if RZSIZE=$(stat -c%s "build/$2/data_seg.rz" 2>/dev/null); then
    :
else
    RZSIZE=$(stat -f%z "build/$2/data_seg.rz")
fi
echo "size=${RZSIZE}"

#fixme as I will fail if position of c_data gets moved!!!
CDATA_POS=$(printf "%d\n" 0x$(grep  ${MAPFILE} -e 'c_data_array' | cut -d "x" -f 2 | cut -d " " -f 1 ))
#CDATA_MAX_SIZE=$(printf "%d\n" 0x$(grep  '${MAPFILE}' -e '.c_data         0x0000000000021990' | cut -d "x" -f 2 ))
#CDATA_POS=137616
CDATA_MAX_SIZE=72704

echo "maxsize=${CDATA_MAX_SIZE}"

[ -x tools/aaa_rip/aaa_rip ] && tools/aaa_rip/aaa_rip build/$2/data_seg.rz $1.tmp 0 0 ${CDATA_POS} || dd if=build/$2/data_seg.rz of=$1.tmp obs=1 seek=${CDATA_POS} conv=notrunc

mv $1.tmp $1
