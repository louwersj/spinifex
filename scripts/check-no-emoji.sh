#!/usr/bin/env bash
# Reject emoji from executable and Go source so terminal output remains plain,
# portable text in interactive shells, log collectors, and CI environments.
set -euo pipefail

if rg -nP '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}]' Makefile \
    --glob '!spinifex/services/spinifexui/frontend/dist/**' \
    scripts cmd spinifex; then
    echo 'Emoji are not permitted in Spinifex source or script output.' >&2
    exit 1
fi
