#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="sound (--symtype 5, undocumented)"
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


## The "sound" symbol type is not documented. It uses a protein
## database, but residues are interpreted with a 31-symbol alphabet:
## -ABCDEFGHIJKLMNOPQRSTUVWXYZabcde (A-Z and a-e are symbols 1 to
## 31). Database residues are stored with NCBIstdaa codes
## (-ABCDEFGHIKLMNPQRSTVWXYZU*OJ), so a protein sequence MKVLAW is read
## as LJSKAT. Default score matrix is IDENTITY_5_1 (+5/-1), default
## gap penalties are 15+5k, and no statistics are available.


#*****************************************************************************#
#                                                                             #
#                                  parameters                                 #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="sound: --symtype 5 is accepted"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: --symtype sound is accepted"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype sound > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: symbol type is reported"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "Symbol type:       Sound" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: default score matrix is IDENTITY_5_1"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "Score matrix:      IDENTITY_5_1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: default gap penalties are 15+5k"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "Gap penalty:       15+5k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: gap penalties can be changed"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 \
        --gapopen 7 \
        --gapextend 3 | \
    grep -qx "Gap penalty:       7+3k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: statistics are not available"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "Statistical parameters are not available for the scoring system specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: a protein database is expected"
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db missing_database \
        --symtype 5 2>&1 | \
    grep -qx "Unable to open file missing_database.pin." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"


#*****************************************************************************#
#                                                                             #
#                            symbols and search                               #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="sound: database residues are read with the sound alphabet"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --symtype 5 \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "LJSKAT" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: identical sequences (score 6 x 5 = 30)"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 \
        --outfmt 7 | \
    grep -qx "      <score>30</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: alignment uses the sound alphabet"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "Sbjct: 1 LJSKAT 6" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: a mismatch scores -1 (score 54 = 11 x 5 - 1)"
DB=$(printf ">s1\nMKVLAWMKVLAW\n" | make_db prot)
printf ">q1\nLJSKATLJXKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 \
        --outfmt 7 | \
    grep -qx "      <score>54</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## symbols: A-Z (uppercase or lowercase) and a-e; lowercase letters
## a-e are distinct symbols, f-z are skipped
DESCRIPTION="sound: uppercase letters are symbols"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nABCDEFGHIJKLMNOPQRSTUVWXYZ\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "Query length:      26 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: lowercase letters a to e are symbols"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nabcde\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "Query length:      5 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: lowercase letters f to z are skipped"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nfghijklmnopqrstuvwxyz\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "Query length:      0 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: lowercase a is not the same symbol as uppercase A"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nljskat\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: '*' and '-' are skipped"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJ*SK-AT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 | \
    grep -qx "Query length:      6 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="sound: tabular output reports raw scores"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 \
        --outfmt 8 | \
    grep -qx "q1	gnl|BL_ORD_ID|0	100.00	6	0	0	1	6	1	6	30" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## other matrices are accepted (their letters are read with the sound
## alphabet)
DESCRIPTION="sound: another built-in matrix can be used"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 \
        --matrix BLOSUM62 | \
    grep -qx "Score matrix:      BLOSUM62" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## matrix files are read with the sound alphabet (J/J = 9 instead of
## 5 with IDENTITY_5_1)
DESCRIPTION="sound: matrix file (sound symbols)"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   J  K\nJ  9 -1\nK -1 7\n" > "${MATRIX}"
printf ">q1\nJ\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 \
        --matrix "${MATRIX}" \
        --outfmt 7 | \
    grep -qx "      <score>9</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

## see known_issues.sh for the ParAlign XML output


exit 0
