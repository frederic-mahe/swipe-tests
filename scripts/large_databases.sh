#!/bin/bash -
# shellcheck disable=SC2015

## Large databases: offsets and counts beyond 32-bit integers.
##
## Not part of run_all_tests.sh: this script writes about 9 GB of
## temporary files (a 4.5 GB FASTA file, then a 4.5 GB database
## volume) and takes several minutes. Run it on its own, with enough
## room in ${TMPDIR} (or in the directory given as second argument):
##
##   bash ./scripts/large_databases.sh ../swipe/swipe [directory]

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="large databases"
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

## all the temporary files go into one directory, removed at the end
WORK_DIR=$(mktemp -d "${2:-${TMPDIR:-/tmp}}/swipe_large.XXXXXX")
trap 'rm -rf "${WORK_DIR}"' EXIT


#*****************************************************************************#
#                                                                             #
#            one volume: more than 2^31 residues, offsets above 2^31          #
#                                                                             #
#*****************************************************************************#

## 2,200,000 protein sequences of 1,000 residues: 2.2 billion residues
## (2^31 = 2,147,483,648), and as many bytes in the sequence file
## (.psq), so that the last sequence offsets are above 2^31. Each
## title is 1,000 characters long: the header file (.phr) is larger
## than 2^31 bytes too. The sequences are windows of a random block,
## except the last one (the target), a random sequence of its own,
## and its title is unique: a search for it reads its residues and its
## header beyond 2^31 bytes. The volume must stay below 4 GB (version
## 4 offsets are 32-bit unsigned integers): makeblastdb -max_file_sz.
SEQUENCES=2200000
LENGTH=1000
RESIDUES=$(( SEQUENCES * LENGTH ))

awk -v sequences="${SEQUENCES}" -v seqlength="${LENGTH}" '
    function random_residues(n,    s, i) {
        s = ""
        for (i = 0 ; i < n ; i++) {
            s = s substr(alphabet, int(rand() * 20) + 1, 1)
        }
        return s
    }
    BEGIN {
        srand(2026)
        alphabet = "ACDEFGHIKLMNPQRSTVWY"
        block = random_residues(2 * seqlength)
        title = random_residues(seqlength - 16)
        for (i = 0 ; i < sequences - 1 ; i++) {
            printf ">sp|L%07d| %s\n%s\n", i, title,
                substr(block, (i * 7) % seqlength + 1, seqlength)
        }
        target = random_residues(seqlength)
        printf ">sp|TARGET| the last sequence %s\n%s\n",
            substr(title, 1, seqlength - 34), target
        print target > "/dev/stderr"
    }' > "${WORK_DIR}/large.fasta" 2> "${WORK_DIR}/target"

makeblastdb \
    -dbtype prot \
    -blastdb_version 4 \
    -in "${WORK_DIR}/large.fasta" \
    -title "large" \
    -parse_seqids \
    -max_file_sz 4GB \
    -out "${WORK_DIR}/large" > /dev/null 2>&1
rm -f "${WORK_DIR}/large.fasta"

## the tests below are worth nothing if the files are not that large
DESCRIPTION="large: a single volume was written"
[[ -s "${WORK_DIR}/large.psq" && ! -e "${WORK_DIR}/large.pal" ]] && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="large: sequence and header files are larger than 2^31 bytes"
[[ $(wc -c < "${WORK_DIR}/large.psq") -gt 2147483648 && \
   $(wc -c < "${WORK_DIR}/large.phr") -gt 2147483648 ]] && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## first 50 residues of the target, as the query
printf ">query\n%s\n" "$(cut -c 1-50 "${WORK_DIR}/target")" > \
       "${WORK_DIR}/query.fasta"

DESCRIPTION="large: residue and sequence counts above 2^31"
"${SWIPE}" \
    --db "${WORK_DIR}/large" \
    --query "${WORK_DIR}/query.fasta" \
    --num_descriptions 1 \
    --num_alignments 0 \
    --num_threads 8 | \
    grep -qx "Database size:     ${RESIDUES} residues in ${SEQUENCES} sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="large: longest sequence"
"${SWIPE}" \
    --db "${WORK_DIR}/large" \
    --query "${WORK_DIR}/query.fasta" \
    --num_descriptions 1 \
    --num_alignments 0 \
    --num_threads 8 | \
    grep -qx "Longest db seq:    ${LENGTH} residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## the last sequence is found, aligned from its first residue, with
## its id: its residues and its header are read beyond 2^31 bytes
DESCRIPTION="large: the last sequence is the best hit (offsets above 2^31)"
"${SWIPE}" \
    --db "${WORK_DIR}/large" \
    --query "${WORK_DIR}/query.fasta" \
    --num_descriptions 1 \
    --num_alignments 1 \
    --num_threads 8 \
    --outfmt 8 | \
    awk -F "\t" '{ print $2, $3, $4, $9, $10 }' | \
    grep -qx "sp|TARGET| 100.00 50 1 50" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="large: the title of the last sequence is shown"
"${SWIPE}" \
    --db "${WORK_DIR}/large" \
    --query "${WORK_DIR}/query.fasta" \
    --num_descriptions 1 \
    --num_alignments 1 \
    --num_threads 8 | \
    grep -q "^>sp|TARGET| the last sequence" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="large: dump of the last sequence (offsets above 2^31)"
"${SWIPE}" \
    --db "${WORK_DIR}/large" \
    --dump 1 < /dev/null | \
    awk '/^>/ { sequence = "" ; next } { sequence = sequence $0 } END { print sequence }' | \
    cmp -s - "${WORK_DIR}/target" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"


#*****************************************************************************#
#                                                                             #
#              two volumes: more than 2^32 residues in all                    #
#                                                                             #
#*****************************************************************************#

## the same volume twice, in an alias file: 4.4 billion residues
## (2^32 = 4,294,967,296), without more disk space
printf "TITLE twice\nDBLIST large large\n" > "${WORK_DIR}/twice.pal"

DESCRIPTION="large: residue counts of two volumes above 2^32"
"${SWIPE}" \
    --db "${WORK_DIR}/twice" \
    --query "${WORK_DIR}/query.fasta" \
    --num_descriptions 1 \
    --num_alignments 0 \
    --num_threads 8 | \
    grep -qx "Database size:     $(( 2 * RESIDUES )) residues in $(( 2 * SEQUENCES )) sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## both copies of the target are found, with the same score
DESCRIPTION="large: the last sequence of each volume is found"
"${SWIPE}" \
    --db "${WORK_DIR}/twice" \
    --query "${WORK_DIR}/query.fasta" \
    --num_descriptions 2 \
    --num_alignments 2 \
    --num_threads 8 \
    --outfmt 8 | \
    awk -F "\t" '{ print $2, $3, $4, $9, $10, $12 }' | \
    uniq -c | \
    grep -q "^ *2 sp|TARGET| 100.00 50 1 50 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## the E-value grows with the size of the database: about twice as
## large for a database twice as large (same score, same query; the
## length adjustment and the rounding of the printed values make it
## not exactly twice)
DESCRIPTION="large: E-value of the target doubles with two volumes"
E_ONE=$("${SWIPE}" \
            --db "${WORK_DIR}/large" \
            --query "${WORK_DIR}/query.fasta" \
            --num_descriptions 1 \
            --num_alignments 1 \
            --num_threads 8 \
            --outfmt 8 | \
            awk -F "\t" '{ print $11 }')
E_TWO=$("${SWIPE}" \
            --db "${WORK_DIR}/twice" \
            --query "${WORK_DIR}/query.fasta" \
            --num_descriptions 1 \
            --num_alignments 1 \
            --num_threads 8 \
            --outfmt 8 | \
            awk -F "\t" '{ print $11 }')
awk -v one="${E_ONE}" -v two="${E_TWO}" \
    'BEGIN { ratio = two / one ; exit ! (one > 0 && ratio > 1.8 && ratio < 2.2) }' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
unset E_ONE E_TWO

exit 0
