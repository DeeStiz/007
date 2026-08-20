#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec "${SCRIPT_DIR}/test_source_product_boot_route_v6.sh" "$@"
