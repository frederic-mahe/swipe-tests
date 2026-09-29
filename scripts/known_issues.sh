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

## KI-43: the numbers of alias files (NSEQ, LENGTH, MAXOID, MEMB_BIT)
## and of score matrix files are not checked: a value that is not a
## number is read as 0, characters after a number are ignored, and an
## out-of-range value is clamped. The alias file selects the second
## sequence of volume 2 (as in database.sh, masked databases).
make_masked_alias () {
    local ALIAS_DIR
    ALIAS_DIR=$(mktemp -d)
    printf ">b1\nMKVWW\n>b2\nMKVY\n" | \
        makeblastdb -dbtype prot -blastdb_version 4 -in - -title "vol2" \
                    -out "${ALIAS_DIR}/vol2" > /dev/null 2>&1
    printf '\x00\x00\x00\x01\x40' > "${ALIAS_DIR}/vol2.msk"
    printf "DBLIST vol2\nOIDLIST vol2.msk\nMEMB_BIT 1\nMAXOID 1\n%s\n" "${1}" > \
           "${ALIAS_DIR}/alias.pal"
    printf "%s/alias\n" "${ALIAS_DIR}"
}

DESCRIPTION="KI-43: alias file: NSEQ that is not a number is read as 0"
DB=$(make_masked_alias $'NSEQ abc\nLENGTH 4')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" 2> /dev/null | \
    grep -qx "Database size:     4 residues in 0 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-43: alias file: characters after NSEQ are ignored"
DB=$(make_masked_alias $'NSEQ 1x\nLENGTH 4')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" 2> /dev/null | \
    grep -qx "Database size:     4 residues in 1 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-43: alias file: an out-of-range LENGTH is clamped"
DB=$(make_masked_alias $'NSEQ 1\nLENGTH 99999999999999999999')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" 2> /dev/null | \
    grep -qx "Database size:     9223372036854775807 residues in 1 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## a negative NSEQ reaches the size of the hit list (std::length_error,
## and std::terminate() without exception handling)
DESCRIPTION="KI-43: alias file: a negative NSEQ aborts"
DB=$(make_masked_alias $'NSEQ -3\nLENGTH 4')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 > /dev/null | \
    grep -q "^terminate called" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-43: matrix file: an out-of-range score is clamped"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -4\nW -4 99999999999999999999\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>9223372036854775807</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

DESCRIPTION="KI-43: matrix file: characters after the last score are ignored"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -4\nW -4 20x\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>20</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

#*****************************************************************************#
#                                                                             #
#                               output formats                                #
#                                                                             #
#*****************************************************************************#

exit 0
