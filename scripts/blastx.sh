#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="blastx (--symtype 2)"
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


## Nucleotide queries translated in six frames (+1 to +3, -1 to -3),
## searched against a protein database.
##
## MKVLAW = ATG AAA GTT CTG GCT TGG
## reverse complement: CCAAGCCAGAACTTTCAT
##
## TGA is a stop codon (*) in the standard genetic code (1), and a
## tryptophan (W) in the vertebrate mitochondrial code (2):
## ATG AAA TGA AAA = MK*K (code 1) or MKWK (code 2)


#*****************************************************************************#
#                                                                             #
#                              default behaviour                              #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="blastx: --symtype 2 is accepted"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: --symtype blastx is accepted"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype blastx > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: query length is reported in nucleotides"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -qx "Query length:      18 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: default matrix is BLOSUM62"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -qx "Score matrix:      BLOSUM62" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: translated query matches (frame +1)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --outfmt 7 | \
    grep -qx "      <qseq>MKVLAW</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: score of the translated query (MKVLAW = 33)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --outfmt 7 | \
    grep -m 1 "<score>" | \
    grep -qx "      <score>33</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: query coordinates are in nucleotides"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --outfmt 8 | \
    head -n 1 | \
    cut -f 3-10 | \
    grep -qx "100.00	6	0	0	1	18	1	6" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## each frame can produce a hit: a database sequence can be reported
## up to six times
DESCRIPTION="blastx: each frame is reported separately (6 hits)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *6" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: plain output, frame of each hit in the list"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep "^gnl|BL_ORD_ID|0 " | \
    awk '{print $3}' | \
    tr "\n" " " | \
    grep -qx "+1 +2 -3 +3 -2 -1 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: plain output, frame line"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -m 1 "^ Frame = " | \
    grep -qx " Frame = +1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: plain output, query coordinates in nucleotides"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -m 1 "^Query: " | \
    grep -qx "Query:  1 MKVLAW 18" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: plain output, subject length in amino acids"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -m 1 "Length = " | \
    grep -qx "          Length = 6" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: frame 2 (one extra nucleotide)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nCATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -m 1 "^ Frame = " | \
    grep -qx " Frame = +2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: frame 3 (two extra nucleotides)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nCCATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -m 1 "^ Frame = " | \
    grep -qx " Frame = +3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: frame 3 (query coordinates)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nCCATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --outfmt 8 | \
    head -n 1 | \
    cut -f 7,8 | \
    grep -qx "3	20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: reverse complemented query (frame -1)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nCCAAGCCAGAACTTTCAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -m 1 "^ Frame = " | \
    grep -qx " Frame = -1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: reverse complemented query (reversed query coordinates)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nCCAAGCCAGAACTTTCAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --outfmt 8 | \
    head -n 1 | \
    cut -f 7-10 | \
    grep -qx "18	1	1	6" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: query shorter than a codon (no hits)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: query of one codon"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --outfmt 8 | \
    cut -f 7-10 | \
    grep -qx "1	3	1	1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: empty query (no hits)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                                query strands                                #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="blastx: --strand 1 searches frames +1, +2 and +3"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 1 | \
    grep "^gnl|BL_ORD_ID|0 " | \
    awk '{print $3}' | \
    tr "\n" " " | \
    grep -qx "+1 +2 +3 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: --strand 2 searches frames -1, -2 and -3"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 2 | \
    grep "^gnl|BL_ORD_ID|0 " | \
    awk '{print $3}' | \
    sort | \
    tr "\n" " " | \
    grep -qx -e "-1 -2 -3 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: --strand is reported in XML output (ParAlign)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 2 \
        --outfmt 99 | \
    grep -q "<queryStrands>Minus</queryStrands>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                         genetic codes and translation                       #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="blastx: standard code, TGA is a stop codon"
DB=$(printf ">p1\nMKWKMKWK\n" | make_db prot)
printf ">q1\nATGAAATGAAAAATGAAATGAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 1 \
        --outfmt 7 | \
    grep -m 1 "<qseq>" | \
    grep -qxF "      <qseq>MK*KMK*K</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: --query_gencode 2, TGA is a tryptophan"
DB=$(printf ">p1\nMKWKMKWK\n" | make_db prot)
printf ">q1\nATGAAATGAAAAATGAAATGAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 1 \
        --query_gencode 2 \
        --outfmt 7 | \
    grep -m 1 "<qseq>" | \
    grep -qx "      <qseq>MKWKMKWK</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: --query_gencode is reported in the parameter block"
DB=$(printf ">p1\nMKWKMKWK\n" | make_db prot)
printf ">q1\nATGAAATGAAAAATGAAATGAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --query_gencode 2 | \
    grep -qx "Query genetic code:Vertebrate Mitochondrial Code (2)" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the database genetic code has no effect on a protein database
DESCRIPTION="blastx: --db_gencode is ignored"
DB=$(printf ">p1\nMKWKMKWK\n" | make_db prot)
printf ">q1\nATGAAATGAAAAATGAAATGAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 1 \
        --db_gencode 2 \
        --outfmt 7 | \
    grep -m 1 "<qseq>" | \
    grep -qxF "      <qseq>MK*KMK*K</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## codons with ambiguous nucleotides are translated when all possible
## codons give the same amino acid (GCN = A), or into B (D or N) and
## Z (E or Q), otherwise X
DESCRIPTION="blastx: ambiguous codons are translated (GCN = A)"
DB=$(printf ">p1\nAAAA\n" | make_db prot)
printf ">q1\nGCNGCNGCNGCN\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 1 \
        --outfmt 7 | \
    grep -m 1 "<qseq>" | \
    grep -qx "      <qseq>AAAA</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: ambiguous codons are translated (RAY = B)"
DB=$(printf ">p1\nBBBB\n" | make_db prot)
printf ">q1\nRAYRAYRAYRAY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 1 \
        --outfmt 7 | \
    grep -m 1 "<qseq>" | \
    grep -qx "      <qseq>BBBB</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: ambiguous codons are translated (SAR = Z)"
DB=$(printf ">p1\nZZZZ\n" | make_db prot)
printf ">q1\nSARSARSARSAR\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 1 \
        --outfmt 7 | \
    grep -m 1 "<qseq>" | \
    grep -qx "      <qseq>ZZZZ</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## X/X scores -1 with BLOSUM62: the alignment stops before the Xs
DESCRIPTION="blastx: ambiguous codons are translated (NNN = X)"
DB=$(printf ">p1\nAAAAXXXX\n" | make_db prot)
printf ">q1\nGCNGCNGCNGCNNNNNNNNNNNNN\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --strand 1 \
        --outfmt 7 | \
    grep -m 1 "<qseq>" | \
    grep -qx "      <qseq>AAAA</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastx: U is read as T in codons"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nAUGAAAGUUCUGGCUUGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --outfmt 7 | \
    grep -m 1 "<qseq>" | \
    grep -qx "      <qseq>MKVLAW</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                                  valgrind                                   #
#                                                                             #
#*****************************************************************************#

if [[ "${VALGRIND_WORKS}" == "true" ]] ; then
    DB=$(printf ">p1\nMKVLAW\n>p2\nMKWKMKWK\n" | make_db prot)
    LOG=$(mktemp)
    printf ">q1\nATGAAAGTTCTGGCTTGG\n>q2\nCCAAGCCAGAACTTTCATNRY\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" \
            --symtype 2 \
            --query_gencode 2 > /dev/null 2>&1
    DESCRIPTION="valgrind: blastx search (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: blastx search (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG
fi


exit 0
