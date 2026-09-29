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

#*****************************************************************************#
#                                                                             #
#                               output formats                                #
#                                                                             #
#*****************************************************************************#

## KI-42: in the long version of a ParAlign XML hit (-m 99), the gi of
## a defline is not reset before the next defline is read: a defline
## without gi gets the gi link of the previous one. Entry with two
## deflines (gi|123|sp|P1|A_HUMAN, sp|P2|B_MOUSE): the gi|123 link is
## shown twice
DESCRIPTION="KI-42: ParAlign XML: a defline without gi inherits a gi link"
DB=$(printf ">gi|123|sp|P1|A_HUMAN first\x01sp|P2|B_MOUSE second\nMKVLAAGIVGLLLAW\n" | \
         make_db prot -parse_seqids)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -c "<longVersionLinkText>gi|123</longVersionLinkText>" | \
    grep -qx "2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

exit 0
