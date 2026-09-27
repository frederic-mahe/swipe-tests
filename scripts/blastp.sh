#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="blastp (--symtype 1)"
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

## valgrind is only useful here if it can actually run the binary under
## test. When it dies before reaching main -- a uprobe on the dynamic
## loader does that, and so does a sanitizer-instrumented binary -- it
## still reports "ERROR SUMMARY: 0 errors" and "in use at exit: 0
## bytes", which would silently turn every valgrind check below into a
## pass. Probe it once here, so those checks are skipped, not passed.
VALGRIND_WORKS=false
if which valgrind > /dev/null 2>&1 ; then
    VALGRIND_PROBE=$(valgrind "${SWIPE}" -h 2>&1)
    [[ "${VALGRIND_PROBE}" == *"ERROR SUMMARY"* && \
       "${VALGRIND_PROBE}" != *"Process terminating"* ]] && \
        VALGRIND_WORKS=true
    unset VALGRIND_PROBE
fi

## repeat a string: repeat STRING COUNT
repeat () {
    local i
    for ((i = 0 ; i < ${2} ; i++)) ; do
        printf "%s" "${1}"
    done
}


## Protein queries against a protein database. Raw alignment scores
## are reported in the XML output (--outfmt 7, <score>), bit scores
## and expect values in the tabular output (--outfmt 8).
##
## BLOSUM62 scores used below: M/M 5, K/K 5, V/V 4, W/W 11, A/A 4,
## P/W -4, A/W -3


#*****************************************************************************#
#                                                                             #
#                              default behaviour                              #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="blastp: default symbol type"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Symbol type:       Amino acid" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: identical sequences (100% identity)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 1 \
        --outfmt 8 | \
    cut -f 1-10 | \
    grep -qx "q1	gnl|BL_ORD_ID|0	100.00	3	0	0	1	3	1	3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: raw score is the sum of BLOSUM62 scores (MKV = 14)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>14</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: a single residue (W = 11)"
DB=$(printf ">s1\nW\n" | make_db prot)
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>11</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: unrelated sequences (no hits)"
DB=$(printf ">s1\nWWW\n" | make_db prot)
printf ">q1\nPPP\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: unrelated sequences (empty tabular output)"
DB=$(printf ">s1\nWWW\n" | make_db prot)
printf ">q1\nPPP\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## local alignments: only the best matching region is reported
DESCRIPTION="blastp: query inside a database sequence (subject coordinates)"
DB=$(printf ">s1\nPPPPPMKVWPPPPP\n" | make_db prot)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 7-10 | \
    grep -qx "1	4	6	9" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: database sequence inside a query (query coordinates)"
DB=$(printf ">s1\nMKVW\n" | make_db prot)
printf ">q1\nPPPPPMKVWPPPPP\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 7-10 | \
    grep -qx "6	9	1	4" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: mismatches are reported"
DB=$(printf ">s1\nMKVWMKVW\n" | make_db prot)
printf ">q1\nMKVWAKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 3-5 | \
    grep -qx "87.50	8	1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## gaps: a 5-residue insertion in the database sequence
DESCRIPTION="blastp: gapped alignment (alignment string)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <alignment>M15I5M12</alignment>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: gapped alignment (score)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>125</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: gapped alignment (gap openings, alignment length)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 3-10 | \
    grep -qx "84.38	32	0	1	1	27	1	32" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: gapped alignment (plain output, gaps)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx " Identities = 27/32 (84%), Positives = 27/32 (84%), Gaps = 5/32 (15%)" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: gapped alignment (plain output, query line)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query:  1 MKVLAAGIVGLLLAW-----KLMNPQRSTVWY 27" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## a deletion in the database sequence (insertion in the query)
DESCRIPTION="blastp: gap in the database sequence (alignment string)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <alignment>M15D5M12</alignment>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: gap in the database sequence (subject line)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Sbjct:  1 MKVLAAGIVGLLLAW-----KLMNPQRSTVWY 27" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## positives: similar residues (positive score), I/V = 3
DESCRIPTION="blastp: positives are counted (I/V)"
DB=$(printf ">s1\nMKVWMKVW\n" | make_db prot)
printf ">q1\nMKIWMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx " Identities = 7/8 (87%), Positives = 8/8 (100%)" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: positives are shown with a '+' in alignments"
DB=$(printf ">s1\nMKVWMKVW\n" | make_db prot)
printf ">q1\nMKIWMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "         MK+WMKVW" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: each database sequence is reported once"
DB=$(printf ">s1\nMKVWPPPPPPPPMKVW\n" | make_db prot)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: hits are sorted by decreasing score"
DB=$(printf ">s1\nMK\n>s2\nMKVW\n>s3\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "lcl|s2 lcl|s3 lcl|s1 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## hits with equal scores: the last database sequence comes first
DESCRIPTION="blastp: ties are sorted by decreasing database order"
DB=$(printf ">s1\nMKV\n>s2\nMKV\n>s3\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "lcl|s3 lcl|s2 lcl|s1 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: many database sequences (500)"
DB=$(for ((i = 1 ; i <= 500 ; i++)) ; do
         printf ">s%d\nMKVW\n" ${i}
     done | make_db prot)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 1000 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *500" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i

## the search goes through 7-bit, 16-bit and 63-bit engines: scores
## higher than 127 and 65,535 must be recomputed
DESCRIPTION="blastp: score above 127 (16-bit search, 20 W = 220)"
DB=$(printf ">s1\n%s\n" "$(repeat W 20)" | make_db prot)
printf ">q1\n%s\n" "$(repeat W 20)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>220</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: score above 65,535 (63-bit search, 6,000 W = 66,000)"
DB=$(printf ">s1\n%s\n" "$(repeat W 6000)" | make_db prot)
printf ">q1\n%s\n" "$(repeat W 6000)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>66000</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: score above 65,535 (alignment)"
DB=$(printf ">s1\n%s\n" "$(repeat W 6000)" | make_db prot)
printf ">q1\n%s\n" "$(repeat W 6000)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <alignment>M6000</alignment>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## (a very high expect value threshold keeps the weakest hit)
DESCRIPTION="blastp: sequences with scores of different magnitudes"
DB=$(printf ">s1\nW\n>s2\n%s\n>s3\n%s\n" \
            "$(repeat W 20)" "$(repeat W 6000)" | make_db prot)
printf ">q1\n%s\n" "$(repeat W 6000)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --evalue 1e9 \
        --outfmt 7 | \
    grep "<score>" | \
    tr -d " " | \
    tr "\n" " " | \
    grep -qx "<score>66000</score> <score>220</score> <score>11</score> " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastp: X residues score -1"
DB=$(printf ">s1\nWXW\n" | make_db prot)
printf ">q1\nWXW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>21</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                         built-in score matrices                             #
#                                                                             #
#*****************************************************************************#

## raw score of a W/W match with each matrix
while read -r MATRIX SCORE ; do
    DESCRIPTION="matrix: ${MATRIX} W/W score is ${SCORE}"
    DB=$(printf ">s1\nW\n" | make_db prot)
    printf ">q1\nW\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --matrix "${MATRIX}" \
            --outfmt 7 | \
        grep -qx "      <score>${SCORE}</score>" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
BLOSUM45 15
BLOSUM50 15
BLOSUM62 11
BLOSUM80 11
BLOSUM90 11
PAM30 13
PAM70 13
PAM250 17
EOF
unset MATRIX SCORE

## statistics are available for all built-in matrices with their
## default gap penalties
for MATRIX in BLOSUM45 BLOSUM50 BLOSUM62 BLOSUM80 BLOSUM90 PAM30 PAM70 PAM250 ; do
    DESCRIPTION="matrix: ${MATRIX} with default gap penalties has statistics"
    DB=$(printf ">s1\nMKVW\n" | make_db prot)
    printf ">q1\nMKVW\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --matrix "${MATRIX}" | \
        grep -q "^Statistical parameters are not available" && \
        failure "${DESCRIPTION}" || \
            success "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset MATRIX

## IDENTITY_5_1 is built-in (for the sound symtype), without
## statistics nor default gap penalties
DESCRIPTION="matrix: IDENTITY_5_1 is available with gap penalties (W/W = 5)"
DB=$(printf ">s1\nW\n" | make_db prot)
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix IDENTITY_5_1 \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>5</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="matrix: IDENTITY_5_1 mismatches score -1"
DB=$(printf ">s1\nWAW\n" | make_db prot)
printf ">q1\nWMW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix IDENTITY_5_1 \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>9</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see known_issues.sh for BLOSUM62_20


#*****************************************************************************#
#                                                                             #
#                          score matrix files                                 #
#                                                                             #
#*****************************************************************************#

## NCBI format: '#' comment lines, a line starting with a space or a
## tab lists the column symbols, then one line per row symbol. Scores
## missing from the file are set to -1. A matrix file requires gap
## penalties (-G and/or -E).

DESCRIPTION="matrix file: scores are read"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "# test matrix\n   A  W\nA  5 -4\nW -4 20\n" > "${MATRIX}"
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

DESCRIPTION="matrix file: name is reported in the parameter block"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -4\nW -4 20\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 | \
    grep -qx "Score matrix:      ${MATRIX}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

DESCRIPTION="matrix file: statistical parameters are not available"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -4\nW -4 20\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 | \
    grep -qx "Statistical parameters are not available for the scoring system specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

DESCRIPTION="matrix file: plain output reports raw scores"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -4\nW -4 20\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 | \
    grep -qx " Score = 20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

DESCRIPTION="matrix file: tabular output reports raw scores (11 columns)"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -4\nW -4 20\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 8 | \
    grep -qx "q1	gnl|BL_ORD_ID|0	100.00	1	0	0	1	1	1	1	20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

## without statistics, expect values cannot filter hits
DESCRIPTION="matrix file: --evalue has no effect without statistics"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -4\nW -4 20\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --evalue 1e-100 \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

DESCRIPTION="matrix file: --min_score filters hits without statistics"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -4\nW -4 20\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --min_score 21 \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

DESCRIPTION="matrix file: missing scores are set to -1"
DB=$(printf ">s1\nWMW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -4\nW -4 20\n" > "${MATRIX}"
printf ">q1\nWMW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>39</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

DESCRIPTION="matrix file: lowercase symbols are accepted"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   a  w\na  5 -4\nw -4 20\n" > "${MATRIX}"
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

DESCRIPTION="matrix file: tab-separated columns are accepted"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "\tA\tW\nA\t5\t-4\nW\t-4\t20\n" > "${MATRIX}"
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

DESCRIPTION="matrix file: unknown symbols are ignored"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W  1\nA  5 -4  7\nW -4 20  7\n1  7  7  7\n" > "${MATRIX}"
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

DESCRIPTION="matrix file: non-numerical score fails"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 x\nW -4 20\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 2>&1 | \
    grep -qx "Problem parsing score matrix file." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

DESCRIPTION="matrix file: empty file (all scores are -1, no hits)"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

## scores are indexed [database residue][query residue]: rows are
## database residues, columns are query residues
DESCRIPTION="matrix file: non-symmetric matrix (query A, database W)"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -9\nW  3 20\n" > "${MATRIX}"
printf ">q1\nA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>3</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

DESCRIPTION="matrix file: non-symmetric matrix (query W, database A)"
DB=$(printf ">s1\nA\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -9\nW  3 20\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

## built-in names take precedence over files with the same name
DESCRIPTION="matrix file: a file named BLOSUM62 is not read"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX_DIR=$(mktemp -d)
printf "   W\nW  99\n" > "${MATRIX_DIR}/BLOSUM62"
(cd "${MATRIX_DIR}" && \
     printf ">q1\nW\n" | \
         "${SWIPE}" \
             --db "${DB}" \
             --matrix BLOSUM62 \
             --outfmt 7) | \
    grep -qx "      <score>11</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${MATRIX_DIR}"
remove_db "${DB}"
unset DB MATRIX_DIR

## scores above 127 are handled by the 16-bit search
DESCRIPTION="matrix file: large positive score (200)"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   W\nW  200\n" > "${MATRIX}"
printf ">q1\nWWW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>200</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

## see fixed_bugs.sh (KI-12, KI-13) for scores below -128 or above
## 32,767


#*****************************************************************************#
#                                                                             #
#                              gap penalties                                  #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="gaps: default penalties 11+1 (a gap of 5 costs 16)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 11 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>125</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="gaps: lower penalties increase the score (9+1: +2)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 9 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>127</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="gaps: extension penalty counts for each gap position (11+2: -5)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 11 \
        --gapextend 2 \
        --outfmt 7 | \
    grep -qx "      <score>120</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## low gap penalties: each isolated residue is aligned with a gap, the
## alignment string is longer than 64 characters
DESCRIPTION="gaps: many gaps (long alignment string)"
DB=$(printf ">s1\n%s\n" "$(repeat WWWA 16)" | make_db prot)
printf ">q1\n%s\n" "$(repeat W 48)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 1 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <alignment>$(repeat M3I1 15)M3</alignment>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## high gap penalties: an ungapped alignment is better
DESCRIPTION="gaps: high penalties prevent gaps (alignment string)"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 100 \
        --gapextend 10 \
        --outfmt 7 | \
    grep -qx "      <alignment>M15</alignment>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## statistics are only available for some gap penalties
for PENALTIES in "11 1" "10 1" "9 2" "12 1" "11 2" ; do
    read -r GAPOPEN GAPEXTEND <<< "${PENALTIES}"
    DESCRIPTION="gaps: BLOSUM62 ${GAPOPEN}+${GAPEXTEND} has statistics"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --gapopen "${GAPOPEN}" \
            --gapextend "${GAPEXTEND}" | \
        grep -q "^Statistical parameters are not available" && \
        failure "${DESCRIPTION}" || \
            success "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset PENALTIES GAPOPEN GAPEXTEND

for PENALTIES in "3 3" "20 5" "1 1" ; do
    read -r GAPOPEN GAPEXTEND <<< "${PENALTIES}"
    DESCRIPTION="gaps: BLOSUM62 ${GAPOPEN}+${GAPEXTEND} has no statistics"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --gapopen "${GAPOPEN}" \
            --gapextend "${GAPEXTEND}" | \
        grep -qx "Statistical parameters are not available for the scoring system specified." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset PENALTIES GAPOPEN GAPEXTEND

## the statistics message is only printed in the plain output
DESCRIPTION="gaps: no statistics message in tabular output"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 3 \
        --gapextend 3 \
        --outfmt 8 | \
    grep -q "Statistical" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see fixed_bugs.sh (KI-11) for gap penalties above 253


#*****************************************************************************#
#                                                                             #
#                    thresholds: expect values and scores                     #
#                                                                             #
#*****************************************************************************#

## database: s1 (15 residues, score 73, E = 4e-08) and s2 (3 residues,
## score 14, E = 0.26), query identical to s1

make_threshold_db () {
    printf ">s1\nMKVLAAGIVGLLLAW\n>s2\nMKV\n" | make_db prot -parse_seqids
}

DESCRIPTION="thresholds: both sequences are reported by default"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "lcl|s1 lcl|s2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: expect values in tabular output"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 11,12 | \
    tr "\n" " " | \
    grep -qx "3.8e-08	32.7 0.26	10.0 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --evalue removes hits above the expect value"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --evalue 0.1 \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "lcl|s1 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --evalue too low (no hits)"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --evalue 1e-10 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: -e is accepted"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -e 0.1 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --minevalue removes hits below the expect value"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --minevalue 1e-5 \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "lcl|s2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: -k is accepted"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -k 1e-5 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --minevalue above all expect values (no hits)"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --minevalue 1 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --minevalue and --evalue define a range"
DB=$(printf ">s1\nMKVLAAGIVGLLLAW\n>s2\nMKVLAAG\n>s3\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --minevalue 1e-6 \
        --evalue 0.1 \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "lcl|s2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --min_score is inclusive (14 keeps score 14)"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --min_score 14 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --min_score removes lower scores (15)"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --min_score 15 \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "lcl|s1 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: -c is accepted"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -c 15 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --min_score above all scores (no hits)"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --min_score 74 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --max_score is inclusive (73 keeps score 73)"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --max_score 73 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --max_score removes higher scores (72)"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --max_score 72 \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "lcl|s2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: -u is accepted"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -u 72 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --max_score below --min_score (no hits)"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --min_score 20 \
        --max_score 10 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the stricter of --evalue and --min_score applies
DESCRIPTION="thresholds: --evalue is stricter than --min_score"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --min_score 1 \
        --evalue 0.1 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --min_score is stricter than --evalue"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --min_score 15 \
        --evalue 10 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## effective database size: expect values are proportional
DESCRIPTION="thresholds: --dbsize changes expect values"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dbsize 1000000 \
        --outfmt 8 | \
    cut -f 11 | \
    head -n 1 | \
    grep -qx "0.0021" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --dbsize does not change bit scores"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dbsize 1000000 \
        --outfmt 8 | \
    cut -f 12 | \
    head -n 1 | \
    grep -qx "32.7" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="thresholds: --dbsize applies to the --evalue threshold"
DB=$(make_threshold_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dbsize 1000000 \
        --evalue 0.001 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see known_issues.sh for --evalue 0


#*****************************************************************************#
#                                                                             #
#            number of descriptions (-v) and alignments (-b)                  #
#                                                                             #
#*****************************************************************************#

## database with three hits for the query MKVW
make_three_hits_db () {
    printf ">s1\nMKVW\n>s2\nMKVY\n>s3\nMKVA\n" | make_db prot
}

DESCRIPTION="limits: all hits are listed by default"
DB=$(make_three_hits_db)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -c "^gnl|BL_ORD_ID" | \
    grep -qx "3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="limits: all hits are aligned by default"
DB=$(make_three_hits_db)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -c "^>gnl|BL_ORD_ID" | \
    grep -qx "3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="limits: --num_descriptions limits the list of hits"
DB=$(make_three_hits_db)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 1 | \
    grep -c "^gnl|BL_ORD_ID" | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="limits: --num_descriptions does not limit alignments"
DB=$(make_three_hits_db)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 1 | \
    grep -c "^>gnl|BL_ORD_ID" | \
    grep -qx "3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="limits: --num_descriptions 0 (empty list of hits)"
DB=$(make_three_hits_db)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 0 | \
    grep -c "^gnl|BL_ORD_ID" | \
    grep -qx "0" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="limits: --num_alignments limits alignments"
DB=$(make_three_hits_db)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 1 | \
    grep -c "^>gnl|BL_ORD_ID" | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="limits: --num_alignments does not limit the list of hits"
DB=$(make_three_hits_db)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 1 | \
    grep -c "^gnl|BL_ORD_ID" | \
    grep -qx "3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="limits: --num_alignments 0 (no alignments)"
DB=$(make_three_hits_db)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 0 | \
    grep -q "^Query: " && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="limits: the best hits are kept"
DB=$(printf ">s1\nMK\n>s2\nMKVW\n>s3\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 2 \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "lcl|s2 lcl|s3 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## more hits than the default limits (250 descriptions, 100 alignments)
DESCRIPTION="limits: default number of descriptions is 250"
DB=$(for ((i = 1 ; i <= 300 ; i++)) ; do
         printf ">s%d\nMKVW\n" ${i}
     done | make_db prot)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -c "^gnl|BL_ORD_ID" | \
    grep -qx "250" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i

DESCRIPTION="limits: default number of alignments is 100"
DB=$(for ((i = 1 ; i <= 300 ; i++)) ; do
         printf ">s%d\nMKVW\n" ${i}
     done | make_db prot)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -c "^>gnl|BL_ORD_ID" | \
    grep -qx "100" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i

## see fixed_bugs.sh (KI-10) for -v 0 -b 0


#*****************************************************************************#
#                                                                             #
#                                  threads                                    #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="threads: results are identical with 1 and 8 threads"
DB=$(for ((i = 1 ; i <= 300 ; i++)) ; do
         printf ">s%d\nMKV%sW\n" ${i} "$(repeat A $(( i % 17 )))"
     done | make_db prot)
diff \
    <(printf ">q1\nMKVAAAAW\n" | \
          "${SWIPE}" \
              --db "${DB}" \
              --num_alignments 300 \
              --num_threads 1 \
              --outfmt 8) \
    <(printf ">q1\nMKVAAAAW\n" | \
          "${SWIPE}" \
              --db "${DB}" \
              --num_alignments 300 \
              --num_threads 8 \
              --outfmt 8) > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i

DESCRIPTION="threads: all hits are found with 8 threads"
DB=$(for ((i = 1 ; i <= 300 ; i++)) ; do
         printf ">s%d\nMKV%sW\n" ${i} "$(repeat A $(( i % 17 )))"
     done | make_db prot)
printf ">q1\nMKVAAAAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 300 \
        --num_threads 8 \
        --evalue 1e9 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *300" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i


#*****************************************************************************#
#                                                                             #
#                                  valgrind                                   #
#                                                                             #
#*****************************************************************************#

if [[ "${VALGRIND_WORKS}" == "true" ]] ; then
    DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n>s2\n%s\n>s3\nMKV\n" \
                "$(repeat W 6000)" | make_db prot)
    LOG=$(mktemp)
    printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n>q2\n%s\n" "$(repeat W 6000)" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" \
            --num_threads 2 > /dev/null 2>&1
    DESCRIPTION="valgrind: blastp search (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: blastp search (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG

    DB=$(printf ">s1\nW\n" | make_db prot)
    MATRIX=$(mktemp)
    printf "# test\n   A  W\nA  5 -9\nW  3 20\n" > "${MATRIX}"
    LOG=$(mktemp)
    printf ">q1\nWA\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" \
            --matrix "${MATRIX}" \
            --gapopen 10 \
            --gapextend 1 > /dev/null 2>&1
    DESCRIPTION="valgrind: matrix file (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: matrix file (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}" "${MATRIX}"
    remove_db "${DB}"
    unset DB LOG MATRIX
fi


exit 0
