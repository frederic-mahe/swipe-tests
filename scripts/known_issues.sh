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

## KI-39: an alias file with a TAXIDLIST (or SEQIDLIST) line, as
## written by blastdb_aliastool -taxidlist (-seqidlist), selects the
## sequences of the listed taxids (or ids). swipe ignores these lines
## and silently searches the whole database (GILIST, by contrast, is
## rejected: "GILIST in database alias files not implemented.")
DESCRIPTION="KI-39: alias with TAXIDLIST, sequences of other taxids are searched"
ALIAS_DIR=$(mktemp -d)
printf ">a1\nMKVW\n>a2\nMKVW\n" | \
    makeblastdb -dbtype prot -blastdb_version 4 -in - -title "vol" -parse_seqids \
                -taxid_map <(printf "a1 9606\na2 10090\n") \
                -out "${ALIAS_DIR}/vol" > /dev/null 2>&1
printf "9606\n" > "${ALIAS_DIR}/taxids.txt"
printf "DBLIST vol\nTAXIDLIST taxids.txt\n" > "${ALIAS_DIR}/filtered.pal"
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${ALIAS_DIR}/filtered" \
        --outfmt 8 2> /dev/null | \
    grep -q "lcl|a2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${ALIAS_DIR}"
unset ALIAS_DIR

DESCRIPTION="KI-39: alias with TAXIDLIST is accepted (exit status 0)"
ALIAS_DIR=$(mktemp -d)
printf ">a1\nMKVW\n>a2\nMKVW\n" | \
    makeblastdb -dbtype prot -blastdb_version 4 -in - -title "vol" -parse_seqids \
                -taxid_map <(printf "a1 9606\na2 10090\n") \
                -out "${ALIAS_DIR}/vol" > /dev/null 2>&1
printf "9606\n" > "${ALIAS_DIR}/taxids.txt"
printf "DBLIST vol\nTAXIDLIST taxids.txt\n" > "${ALIAS_DIR}/filtered.pal"
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${ALIAS_DIR}/filtered" > /dev/null 2>&1 && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${ALIAS_DIR}"
unset ALIAS_DIR

DESCRIPTION="KI-39: alias with SEQIDLIST, other sequences are searched"
ALIAS_DIR=$(mktemp -d)
printf ">a1\nMKVW\n>a2\nMKVW\n" | \
    makeblastdb -dbtype prot -blastdb_version 4 -in - -title "vol" -parse_seqids \
                -out "${ALIAS_DIR}/vol" > /dev/null 2>&1
printf "DBLIST vol\nSEQIDLIST ids.bsl\n" > "${ALIAS_DIR}/filtered.pal"
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${ALIAS_DIR}/filtered" \
        --outfmt 8 2> /dev/null | \
    grep -c "lcl|a" | \
    grep -qx "2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${ALIAS_DIR}"
unset ALIAS_DIR

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


exit 0
