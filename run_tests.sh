#!/bin/sh

# Automated sample test runner for TaskLang++.
# Valid samples must exit with 0; invalid samples must exit with non-zero.

set -u

valid_count=0
invalid_count=0
fail_count=0

printf 'Building TaskLang++...\n'
if ! make >/dev/null; then
    printf 'Build failed.\n'
    exit 1
fi

printf '\nRunning valid samples...\n'
for file in samples/valid/*.tl; do
    valid_count=$((valid_count + 1))

    if ./tasklang < "$file" >/dev/null 2>&1; then
        printf '  PASS valid:   %s\n' "$file"
    else
        printf '  FAIL valid:   %s\n' "$file"
        fail_count=$((fail_count + 1))
    fi
done

printf '\nRunning invalid samples...\n'
for file in samples/invalid/*.tl; do
    invalid_count=$((invalid_count + 1))

    if ./tasklang < "$file" >/dev/null 2>&1; then
        printf '  FAIL invalid: %s unexpectedly passed\n' "$file"
        fail_count=$((fail_count + 1))
    else
        printf '  PASS invalid: %s\n' "$file"
    fi
done

printf '\nTest summary:\n'
printf '  Valid samples checked:   %d\n' "$valid_count"
printf '  Invalid samples checked: %d\n' "$invalid_count"
printf '  Failures:                %d\n' "$fail_count"

if [ "$fail_count" -ne 0 ]; then
    exit 1
fi

printf '\nAll sample tests passed.\n'
exit 0
