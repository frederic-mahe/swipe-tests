#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="known issues"
LINE=$(printf "%76s\n" " " | tr " " "-")
printf "# %s %s\n" "${LINE:${#SCRIPT_NAME}}" "${SCRIPT_NAME}"

## Declare a color code for test results
RED="\033[1;31m"
GREEN="\033[1;32m"
NO_COLOR="\033[0m"

failure () {
    printf "%bFAIL%b: %s\n" "${RED}" "${NO_COLOR}" "${1}"
    exit 1
}

success () {
    printf "%bPASS%b: %s\n" "${GREEN}" "${NO_COLOR}" "${1}"
}

## use the first swipe binary in $PATH by default, unless user wants
## to test another binary
SWIPE=$(which swipe 2> /dev/null)
[[ "${1}" ]] && SWIPE="${1}"

## make the path absolute, as some tests change directory
## (readlink -f is missing from older versions of macOS)
[[ -x "${SWIPE}" ]] && \
    SWIPE="$(cd "$(dirname "${SWIPE}")" && pwd)/$(basename "${SWIPE}")"

DESCRIPTION="check if swipe is executable"
[[ -x "${SWIPE}" ]] && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## swipe only reads BLAST databases (format version 4), created here
## with makeblastdb (NCBI BLAST+)
DESCRIPTION="check if makeblastdb is executable"
which makeblastdb > /dev/null 2>&1 && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## create a temporary database from the fasta sequences read on
## stdin. The first argument is the database type (prot or nucl),
## other arguments are passed to makeblastdb. Print the database
## base name.
make_db () {
    local DB_DIR
    DB_DIR=$(mktemp -d)
    makeblastdb \
        -dbtype "${1}" \
        -blastdb_version 4 \
        -in - \
        -title "test" \
        -out "${DB_DIR}/db" \
        "${@:2}" > /dev/null 2>&1
    printf "%s/db\n" "${DB_DIR}"
}

## delete a database created with make_db
remove_db () {
    rm -rf "$(dirname "${1}")"
}

## These tests pin the current behaviour of swipe 2.1.1 in situations
## that are, or look like, bugs. Each test is expected to fail once
## the corresponding issue is fixed: the test should then be updated
## to pin the new behaviour (and moved to fixed_bugs.sh).
##
## Issues are numbered KI-1 to KI-36, as in the file
## TBD_20260926_potential_issues.md (swipe repository), where they are
## described in details.


#*****************************************************************************#
#                                                                             #
#                            command-line options                             #
#                                                                             #
#*****************************************************************************#

#*****************************************************************************#
#                                                                             #
#                       search engines and score ranges                       #
#                                                                             #
#*****************************************************************************#

#*****************************************************************************#
#                                                                             #
#                               query parsing                                 #
#                                                                             #
#*****************************************************************************#

#*****************************************************************************#
#                                                                             #
#                                  databases                                  #
#                                                                             #
#*****************************************************************************#

## KI-41: in a Date-std (the release date of a PDB identifier), the
## hour [4] is detected, then matched with the tag of the minute [5]:
## a date with an hour is rejected. makeblastdb writes no dates, so the
## chain name of a PDB identifier (30 bytes at offset 33 of the header
## file) is replaced by a release date of the same length: [2] {
## std [1] { SEQUENCE { year [0] 2025, hour [4] 12 } } }
DESCRIPTION="KI-41: a PDB release date with an hour is rejected"
DB=$(printf ">pdb|1ABC|AAAAAAAAAAAAAAAAAAAAAAAA title\nMKV\n" | \
         make_db prot -parse_seqids)
printf '\xa2\x80\xa1\x80\x30\x80\xa0\x80\x02\x04\x00\x00\x07\xe9\x00\x00\xa4\x80\x02\x02\x00\x0c\x00\x00\x00\x00\x00\x00\x00\x00' | \
    dd of="${DB}.phr" bs=1 seek=33 count=30 conv=notrunc 2> /dev/null
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null 2>&1 | \
    grep -qx "Unexpected object a4, expected a5." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

#*****************************************************************************#
#                                                                             #
#                               output formats                                #
#                                                                             #
#*****************************************************************************#

exit 0
