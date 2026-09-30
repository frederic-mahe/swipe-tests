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

## The sanitizer checks below need a binary built with the address
## sanitizer (for instance with: make DEBUG=1), as in fixed_bugs.sh
SWIPE_HAS_ASAN=false
ASAN_OPTIONS=help=1 "${SWIPE}" -h 2>&1 | \
    grep -q "AddressSanitizer" && SWIPE_HAS_ASAN=true

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

## KI-46: the entries of the ambiguity table of a nucleotide sequence
## (a code, a run length, a position) are not checked against the
## length of the sequence: a corrupted entry writes past the buffer
## of the sequence (decision Q63: fatal). ACGTNACGTA has one entry, at
## offset 8 of the sequence file, "f0 00 00 04" (the code of N at
## position 4): the position becomes 11, past the 10 bases
if [[ "${SWIPE_HAS_ASAN}" == "true" ]] ; then
    DESCRIPTION="KI-46: an ambiguity past the sequence overflows the buffer (ASan)"
    DB=$(printf ">s1\nACGTNACGTA\n" | make_db nucl)
    printf '\x0b' | dd of="${DB}.nsq" bs=1 seek=11 count=1 conv=notrunc 2> /dev/null
    printf ">q1\nACGTNACGTA\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype 0 \
            --outfmt 8 2>&1 > /dev/null | \
        grep -q "ERROR: AddressSanitizer: heap-buffer-overflow" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
else
    DESCRIPTION="KI-46: an ambiguity past the sequence is accepted"
    DB=$(printf ">s1\nACGTNACGTA\n" | make_db nucl)
    printf '\x0b' | dd of="${DB}.nsq" bs=1 seek=11 count=1 conv=notrunc 2> /dev/null
    printf ">q1\nACGTNACGTA\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype 0 \
            --outfmt 8 > /dev/null 2>&1 && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
fi

#*****************************************************************************#
#                                                                             #
#                               output formats                                #
#                                                                             #
#*****************************************************************************#

exit 0
