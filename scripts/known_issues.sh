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

## KI-2: --help exits with status 1 (GNU convention is 0)
DESCRIPTION="KI-2: --help exits with status 1"
"${SWIPE}" --help > /dev/null 2>&1
(( $? == 1 )) && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## KI-6: zero means "default value", so a null gap open or gap
## extension penalty cannot be used
DESCRIPTION="KI-6: --gapopen 0 is replaced by 11 (BLOSUM62)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 0 \
        --gapextend 1 | \
    grep -qx "Gap penalty:       11+1k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-6: --gapopen 0 is replaced by 5 (blastn)"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --gapopen 0 | \
    grep -qx "Gap penalty:       5+2k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-6: --gapextend 0 is replaced by 2 (blastn)"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --gapopen 3 \
        --gapextend 0 | \
    grep -qx "Gap penalty:       3+2k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

#*****************************************************************************#
#                                                                             #
#                       search engines and score ranges                       #
#                                                                             #
#*****************************************************************************#

## KI-15: BLOSUM62_20 has statistical parameters and default gap
## penalties, but no built-in matrix
DESCRIPTION="KI-15: BLOSUM62_20 has default gap penalties"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix BLOSUM62_20 2>&1 | \
    grep -q "Unknown score matrix" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-15: BLOSUM62_20 is searched as a file"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix BLOSUM62_20 2>&1 | \
    grep -qx "Cannot open score matrix file." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


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

## KI-26: simple XML (--outfmt 7) has one root element per query
DESCRIPTION="KI-26: XML, several queries produce several root elements"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -c "^<result>" | \
    grep -qx "2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-36: with tblastn, the simple XML output reports the length
## of the translated database sequence (amino acids), other outputs
## report the length of the database sequence (nucleotides)
DESCRIPTION="KI-36: tblastn, XML length is in amino acids (6, not 22)"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --outfmt 7 | \
    grep -m 1 "<len>" | \
    grep -qx "      <len>6</len>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


exit 0
