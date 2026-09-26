#!/bin/bash

## Launch all tests

## tests use the first swipe binary in $PATH by default, use ${1} to
## point to another binary

## Declare a color code for the final verdict
RED="\033[1;31m"
GREEN="\033[1;32m"
NO_COLOR="\033[0m"

## The run stops at the first failing test script (failure() exits, and
## so does this runner). Without a final verdict, a complete run and a
## run that died early -- wrong binary path, interrupted, killed --
## both end without printing a FAIL line, and cannot be told apart by
## the caller. Report the outcome in one greppable line, always.
CURRENT_SCRIPT=""
SCRIPT_NUMBER=0

# shellcheck disable=SC2329  # invoked indirectly, by the EXIT trap below
report_verdict () {
    local STATUS=$?
    if [[ "${STATUS}" -eq 0 ]] ; then
        printf "%bSUMMARY: OK - all %d test scripts completed%b\n" \
               "${GREEN}" "${SCRIPT_NUMBER}" "${NO_COLOR}"
    elif [[ -z "${CURRENT_SCRIPT}" ]] ; then
        printf "%bSUMMARY: ABORTED - no test script was started%b\n" \
               "${RED}" "${NO_COLOR}"
    else
        printf "%bSUMMARY: ABORTED - stopped in scripts/%s (test script number %d)%b\n" \
               "${RED}" "${CURRENT_SCRIPT}" "${SCRIPT_NUMBER}" "${NO_COLOR}"
    fi
    exit "${STATUS}"
}

trap report_verdict EXIT

run_test_script () {
    CURRENT_SCRIPT="${1}"
    SCRIPT_NUMBER=$(( SCRIPT_NUMBER + 1 ))
    bash "./scripts/${1}" "${2}" || exit 1
    echo
}

## general tests
for test_script in options.sh \
                       query.sh \
                       database.sh \
                       output.sh ; do
    run_test_script "${test_script}" "${1}"
done

## search-specific tests (one per symbol type)
for test_script in blastn.sh \
                       blastp.sh \
                       blastx.sh \
                       tblastn.sh \
                       tblastx.sh \
                       sound.sh ; do
    run_test_script "${test_script}" "${1}"
done

## regressions and known issues
for test_script in fixed_bugs.sh \
                       known_issues.sh ; do
    run_test_script "${test_script}" "${1}"
done

exit 0
