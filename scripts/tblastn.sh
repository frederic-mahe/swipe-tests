#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="tblastn (--symtype 3)"
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


## Protein queries against a nucleotide database translated in six
## frames.
##
## MKVLAW = ATG AAA GTT CTG GCT TGG, here in frame +3 of the database
## sequence GGATGAAAGTTCTGGCTTGGCC (22 nucleotides)
##
## TGA is a stop codon (*) in the standard genetic code (1), and a
## tryptophan (W) in the vertebrate mitochondrial code (2)


#*****************************************************************************#
#                                                                             #
#                              default behaviour                              #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="tblastn: --symtype 3 is accepted"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: --symtype tblastn is accepted"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype tblastn > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: query length is reported in amino acids"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 | \
    grep -qx "Query length:      6 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: database size is reported in nucleotides"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 | \
    grep -qx "Database size:     22 residues in 1 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: translated database sequence matches (frame +3)"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 | \
    grep -m 1 "^ Frame = " | \
    grep -qx " Frame = +3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: subject coordinates are in nucleotides"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --outfmt 8 | \
    head -n 1 | \
    cut -f 3-10 | \
    grep -qx "100.00	6	0	0	1	6	3	20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: score of the translated subject (MKVLAW = 33)"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --outfmt 7 | \
    grep -m 1 "<score>" | \
    grep -qx "      <score>33</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: plain output, subject length in nucleotides"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 | \
    grep -m 1 "Length = " | \
    grep -qx "          Length = 22" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the simple XML output reports the length of the translated frame
DESCRIPTION="tblastn: XML output, subject length in amino acids"
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

DESCRIPTION="tblastn: ParAlign XML output, subject length in nucleotides"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --outfmt 99 | \
    grep -m 1 "<databaseSequenceLength>" | \
    grep -q "<databaseSequenceLength>22 nt</databaseSequenceLength>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: plain output, subject coordinates in nucleotides"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 | \
    grep -m 1 "^Sbjct: " | \
    grep -qx "Sbjct:  3 MKVLAW 20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: each frame is reported separately"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *6" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: reverse complemented subject (frame -1)"
DB=$(printf ">n1\nCCAAGCCAGAACTTTCAT\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 | \
    grep -m 1 "^ Frame = " | \
    grep -qx " Frame = -1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: reverse complemented subject (reversed coordinates)"
DB=$(printf ">n1\nCCAAGCCAGAACTTTCAT\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --outfmt 8 | \
    head -n 1 | \
    cut -f 7-10 | \
    grep -qx "1	6	18	1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: database sequence shorter than a codon (no hits)"
DB=$(printf ">n1\nAT\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: ambiguous database nucleotides are translated (GCN = A)"
DB=$(printf ">n1\nGCNGCNGCNGCN\n" | make_db nucl)
printf ">q1\nAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --outfmt 7 | \
    grep -m 1 "<dseq>" | \
    grep -qx "      <dseq>AAAA</dseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## (only frame +3 has an expect value below 0.05)
DESCRIPTION="tblastn: many database sequences (100)"
DB=$(for ((i = 1 ; i <= 100 ; i++)) ; do
         printf ">n%d\nGGATGAAAGTTCTGGCTTGGCC\n" ${i}
     done | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --num_threads 4 \
        --num_alignments 1000 \
        --evalue 0.05 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *100" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i


#*****************************************************************************#
#                                                                             #
#                                genetic codes                                #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="tblastn: standard code, TGA is a stop codon"
DB=$(printf ">n1\nATGAAATGAAAAATGAAATGAAAA\n" | make_db nucl)
printf ">q1\nMKWKMKWK\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --outfmt 7 | \
    grep -m 1 "<dseq>" | \
    grep -qxF "      <dseq>MK*KMK*K</dseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: --db_gencode 2, TGA is a tryptophan"
DB=$(printf ">n1\nATGAAATGAAAAATGAAATGAAAA\n" | make_db nucl)
printf ">q1\nMKWKMKWK\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --db_gencode 2 \
        --outfmt 7 | \
    grep -m 1 "<dseq>" | \
    grep -qx "      <dseq>MKWKMKWK</dseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastn: --query_gencode is ignored"
DB=$(printf ">n1\nATGAAATGAAAAATGAAATGAAAA\n" | make_db nucl)
printf ">q1\nMKWKMKWK\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --query_gencode 2 \
        --outfmt 7 | \
    grep -m 1 "<dseq>" | \
    grep -qxF "      <dseq>MK*KMK*K</dseq>" && \
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
    DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n>n2\nCCAAGCCAGAACTTTCATNNRY\n" | make_db nucl)
    LOG=$(mktemp)
    printf ">q1\nMKVLAW\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" \
            --symtype 3 > /dev/null 2>&1
    DESCRIPTION="valgrind: tblastn search (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: tblastn search (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG
fi


exit 0
