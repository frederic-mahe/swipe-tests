#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="tblastx (--symtype 4)"
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


## Nucleotide queries translated in six frames, against a nucleotide
## database translated in six frames (36 frame combinations).
##
## MKVLAW = ATG AAA GTT CTG GCT TGG, in frame +1 of the query
## ATGAAAGTTCTGGCTTGG, and in frame +3 of the database sequence
## GGATGAAAGTTCTGGCTTGGCC (22 nucleotides)


#*****************************************************************************#
#                                                                             #
#                              default behaviour                              #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="tblastx: --symtype 4 is accepted"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: --symtype tblastx is accepted"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype tblastx > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: query length is reported in nucleotides"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 | \
    grep -qx "Query length:      18 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: both genetic codes are reported"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 | \
    grep -c "genetic code:" | \
    grep -qx "2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the reverse complements of both sequences also match (frames
## -1/-3), with a slightly higher score than MKVLAW (frames +1/+3)
DESCRIPTION="tblastx: best hit, frames -1/-3"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 | \
    grep -m 1 "^ Frame = " | \
    grep -qx " Frame = -1 / -3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: frames +1/+3 are reported"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 | \
    grep -qx " Frame = +1 / +3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: plain output, frames in the list of hits"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 | \
    grep "^gnl|BL_ORD_ID|0 " | \
    head -n 2 | \
    awk '{print $3}' | \
    tr "\n" " " | \
    grep -qx -e "-1/-3 +1/+3 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: query and subject coordinates are in nucleotides"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --outfmt 8 | \
    cut -f 3-10 | \
    grep -qx "100.00	6	0	0	1	18	3	20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: reversed query and subject coordinates (frames -1/-3)"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --outfmt 8 | \
    head -n 1 | \
    cut -f 3-10 | \
    grep -qx "100.00	6	0	0	18	1	20	3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: both strands reversed (-1/-3)"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 | \
    grep "^gnl|BL_ORD_ID|0 " | \
    awk '{print $3}' | \
    grep -qx -e "-1/-3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: plain output, subject length in nucleotides"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 | \
    grep -m 1 "Length = " | \
    grep -qx "          Length = 22" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: --strand 1 searches only the plus strand of the query"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --strand 1 | \
    grep "^gnl|BL_ORD_ID|0 " | \
    awk '{print substr($3, 1, 1)}' | \
    sort -u | \
    grep -qx "+" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see known_issues.sh for --strand 2


#*****************************************************************************#
#                                                                             #
#                       genetic codes and statistics                          #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="tblastx: --query_gencode 2 and --db_gencode 2 (TGA = W)"
DB=$(printf ">n1\nATGAAATGAAAAATGAAATGAAAA\n" | make_db nucl)
printf ">q1\nATGAAATGAAAAATGAAATGAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --query_gencode 2 \
        --db_gencode 2 \
        --outfmt 7 | \
    grep -m 1 "<qseq>" | \
    grep -qx "      <qseq>MKWKMKWK</qseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="tblastx: different query and database genetic codes (* vs W)"
DB=$(printf ">n1\nATGAAATGAAAAATGAAATGAAAA\n" | make_db nucl)
printf ">q1\nATGAAATGAAAAATGAAATGAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --query_gencode 1 \
        --db_gencode 2 \
        --outfmt 7 | \
    grep -A 2 -xF "      <qseq>MK*KMK*K</qseq>" | \
    grep -qx "      <dseq>MKWKMKWK</dseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## statistics are computed with ungapped parameters, so they are
## available even for gap penalties without gapped statistics
DESCRIPTION="tblastx: statistics with gap penalties 3+3"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --gapopen 3 \
        --gapextend 3 | \
    grep -q "^Statistical parameters are not available" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## (only frames -1/-3 have an expect value below 0.01)
DESCRIPTION="tblastx: many database sequences (100)"
DB=$(for ((i = 1 ; i <= 100 ; i++)) ; do
         printf ">n%d\nGGATGAAAGTTCTGGCTTGGCC\n" ${i}
     done | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --num_threads 4 \
        --num_alignments 1000 \
        --evalue 0.01 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *100" && \
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
    DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n>n2\nCCAAGCCAGAACTTTCATNNRY\n" | make_db nucl)
    LOG=$(mktemp)
    printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" \
            --symtype 4 > /dev/null 2>&1
    DESCRIPTION="valgrind: tblastx search (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: tblastx search (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG
fi


exit 0
