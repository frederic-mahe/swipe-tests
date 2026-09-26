#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="blastn (--symtype 0)"
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


## Nucleotide queries against a nucleotide database. By default,
## matches score 1, mismatches -3, gaps 5+2k, and both query strands
## are searched. Minus-strand hits are reported with reversed subject
## coordinates.
##
## the database sequence AAAACCCCGGGGTTTTACGA used below: its reverse
## complement is TCGTAAAACCCCGGGGTTTT, which contains its first 16
## nucleotides (AAAACCCCGGGGTTTT is a palindrome)


#*****************************************************************************#
#                                                                             #
#                              default behaviour                              #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="blastn: --symtype 0 is accepted"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: --symtype blastn is accepted"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype blastn > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: identical sequences (100% identity)"
DB=$(printf ">s1\nACGTTGCAAGGCTTAACCGT\n" | make_db nucl)
printf ">q1\nACGTTGCAAGGCTTAACCGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 8 | \
    cut -f 1-10 | \
    grep -qx "q1	gnl|BL_ORD_ID|0	100.00	20	0	0	1	20	1	20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: raw score is the number of matches (default reward 1)"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 7 | \
    grep -qx "      <score>10</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: a mismatch costs 3 (default penalty -3)"
DB=$(printf ">s1\nAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nAAAAACAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 7 | \
    grep -qx "      <score>6</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: unrelated sequences (no hits)"
DB=$(printf ">s1\nAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nCCCCCCCCCC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the gap could be placed after position 19 or 20 (TT vs T), swipe
## places it leftmost
DESCRIPTION="blastn: gapped alignment (alignment string)"
DB=$(printf ">s1\nACGTTGCAAGGCTTAACCGTACGTTGCAAGG\n" | make_db nucl)
printf ">q1\nACGTTGCAAGGCTTAACCGTTTACGTTGCAAGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 7 | \
    grep -qx "      <alignment>M19D2M12</alignment>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: gapped alignment (score, gap penalties 5+2k)"
DB=$(printf ">s1\nACGTTGCAAGGCTTAACCGTACGTTGCAAGG\n" | make_db nucl)
printf ">q1\nACGTTGCAAGGCTTAACCGTTTACGTTGCAAGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 7 | \
    grep -qx "      <score>22</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: plain output shows identities but no positives"
DB=$(printf ">s1\nACGTTGCAAGGCTTAACCGT\n" | make_db nucl)
printf ">q1\nACGTTGCAAGGCTTAACCGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 | \
    grep -qx " Identities = 20/20 (100%)" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: plain output shows lowercase nucleotides"
DB=$(printf ">s1\nACGTTGCAAGGCTTAACCGT\n" | make_db nucl)
printf ">q1\nACGTTGCAAGGCTTAACCGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 | \
    grep -qx "Query:  1 acgttgcaaggcttaaccgt 20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: plain output shows identities with '|'"
DB=$(printf ">s1\nACGTTGCAAGGCTTAACCGT\n" | make_db nucl)
printf ">q1\nACGTTGCAACGCTTAACCGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 | \
    grep -qx "          ||||||||| ||||||||||" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## ambiguity codes are compared as symbols: identical codes match,
## different codes (even compatible ones) mismatch
DESCRIPTION="blastn: N matches N (score 9 = 8 + 1)"
DB=$(printf ">s1\nACGTNACGT\n" | make_db nucl)
printf ">q1\nACGTNACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 7 | \
    grep -qx "      <score>9</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: A mismatches N (score 5 = 8 - 3)"
DB=$(printf ">s1\nACGTNACGT\n" | make_db nucl)
printf ">q1\nACGTAACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 7 | \
    grep -qx "      <score>5</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: A mismatches R (A or G) (score 5 = 8 - 3)"
DB=$(printf ">s1\nACGTRACGT\n" | make_db nucl)
printf ">q1\nACGTAACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 7 | \
    grep -qx "      <score>5</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: R matches R (score 9 = 8 + 1)"
DB=$(printf ">s1\nACGTRACGT\n" | make_db nucl)
printf ">q1\nACGTRACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 7 | \
    grep -qx "      <score>9</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: many database sequences (500)"
DB=$(for ((i = 1 ; i <= 500 ; i++)) ; do
         printf ">s%d\nACGTTGCAAGGCTTAACCGT\n" ${i}
     done | make_db nucl)
printf ">q1\nACGTTGCAAGGCTTAACCGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --num_alignments 1000 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *500" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i

DESCRIPTION="blastn: long sequences (score above 127, 16-bit search)"
DB=$(printf ">s1\n%s\n" "$(printf "%0200d" 0 | tr "0" "A")" | make_db nucl)
printf ">q1\n%s\n" "$(printf "%0200d" 0 | tr "0" "A")" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 7 | \
    grep -qx "      <score>200</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="blastn: scores above 65,535 (63-bit search, reward 100)"
DB=$(printf ">s1\n%s\n" "$(printf "%0700d" 0 | tr "0" "A")" | make_db nucl)
printf ">q1\n%s\n" "$(printf "%0700d" 0 | tr "0" "A")" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --reward 100 \
        --outfmt 7 | \
    grep -qx "      <score>70000</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                              query strands                                  #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="strands: both strands are searched by default"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## a database sequence can be reported twice, once per strand
DESCRIPTION="strands: plus and minus hits are reported separately"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --outfmt 8 | \
    cut -f 2 | \
    uniq | \
    grep -qx "gnl|BL_ORD_ID|0" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: minus-strand hit (reversed subject coordinates)"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand minus \
        --outfmt 8 | \
    cut -f 3-10 | \
    grep -qx "100.00	20	0	0	1	20	20	1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: plus-strand hit (direct coordinates)"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand plus \
        --outfmt 8 | \
    cut -f 3-10 | \
    grep -qx "100.00	16	0	0	5	20	1	16" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: --strand 1 searches only the plus strand"
DB=$(printf ">s1\nAAAAAAAAAAAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nTTTTTTTTTTTTTTTTTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: --strand 2 searches only the minus strand"
DB=$(printf ">s1\nAAAAAAAAAAAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nAAAAAAAAAAAAAAAAAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: --strand 2 finds reverse-complemented sequences"
DB=$(printf ">s1\nAAAAAAAAAAAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nTTTTTTTTTTTTTTTTTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 \
        --outfmt 8 | \
    cut -f 9,10 | \
    grep -qx "20	1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: --strand both is the same as the default"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
diff \
    <(printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
          "${SWIPE}" \
              --db "${DB}" \
              --symtype 0 \
              --outfmt 8) \
    <(printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
          "${SWIPE}" \
              --db "${DB}" \
              --symtype 0 \
              --strand both \
              --outfmt 8) > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: plain output, minus strand marker in the list"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 | \
    grep -Eqx "gnl\|BL_ORD_ID\|0 s1 +- +40 +2e-10" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: plain output, plus strand marker in the list"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 | \
    grep -Eqx "gnl\|BL_ORD_ID\|0 s1 +\+ +32 +6e-08" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: plain output, strand line of a minus-strand hit"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 | \
    grep -qx " Strand = Plus / Minus" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: plain output, strand line of a plus-strand hit"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 | \
    grep -qx " Strand = Plus / Plus" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: plain output, subject coordinates of a minus-strand hit"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 | \
    grep -qx "Sbjct: 20 tcgtaaaaccccggggtttt 1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: XML output, subject positions of a minus-strand hit"
DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n" | make_db nucl)
printf ">q1\nTCGTAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 \
        --outfmt 7 | \
    grep -qx "      <dpos>20,1</dpos>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## equal scores: the plus-strand hit comes first
DESCRIPTION="strands: palindromic query, both strands hit"
DB=$(printf ">s1\nAAAACCCCGGGGTTTT\n" | make_db nucl)
printf ">q1\nAAAACCCCGGGGTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --outfmt 8 | \
    cut -f 9,10 | \
    tr "\n" " " | \
    grep -qx "1	16 16	1 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="strands: ambiguous nucleotides are complemented"
DB=$(printf ">s1\nAAAAARRRRRAAAAA\n" | make_db nucl)
printf ">q1\nTTTTTYYYYYTTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 \
        --outfmt 7 | \
    grep -qx "      <score>15</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                        match reward and mismatch penalty                    #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="scores: --reward changes the match score"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --reward 2 \
        --penalty -3 \
        --outfmt 7 | \
    grep -qx "      <score>20</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="scores: --penalty changes the mismatch score"
DB=$(printf ">s1\nAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nAAAAACAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --penalty -1 \
        --outfmt 7 | \
    grep -qx "      <score>8</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="scores: --reward 0 (no hits)"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --reward 0 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="scores: negative --reward (no hits)"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --reward -1 | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## a positive mismatch penalty rewards mismatches
DESCRIPTION="scores: positive --penalty rewards mismatches"
DB=$(printf ">s1\nAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nCCCCCCCCCC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --penalty 1 \
        --outfmt 7 | \
    grep -qx "      <score>10</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## statistics (Karlin-Altschul parameters) exist only for some
## combinations of reward, penalty and gap penalties
for SCORES in "1 -2" "1 -3" "1 -4" "2 -3" "3 -4" "4 -5" ; do
    read -r REWARD PENALTY <<< "${SCORES}"
    DESCRIPTION="scores: ${REWARD}/${PENALTY} with gaps 5+2 has statistics"
    DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
    printf ">q1\nACGTACGTAC\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype 0 \
            --reward "${REWARD}" \
            --penalty "${PENALTY}" | \
        grep -q "^Statistical parameters are not available" && \
        failure "${DESCRIPTION}" || \
            success "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset SCORES REWARD PENALTY

for SCORES in "1 -1" "1 -5" "2 -5" "2 -7" "3 -2" "5 -4" "2 -2" "1 -6" ; do
    read -r REWARD PENALTY <<< "${SCORES}"
    DESCRIPTION="scores: ${REWARD}/${PENALTY} with gaps 5+2 has no statistics"
    DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
    printf ">q1\nACGTACGTAC\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype 0 \
            --reward "${REWARD}" \
            --penalty "${PENALTY}" | \
        grep -qx "Statistical parameters are not available for the scoring system specified." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset SCORES REWARD PENALTY

## gap penalties higher than the table maximum use ungapped statistics
DESCRIPTION="scores: 1/-3 with large gap penalties has statistics"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --gapopen 50 \
        --gapextend 50 | \
    grep -q "^Statistical parameters are not available" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="scores: 1/-3 with gaps 3+1 has no statistics"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --gapopen 3 \
        --gapextend 1 | \
    grep -qx "Statistical parameters are not available for the scoring system specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="scores: without statistics, tabular output has raw scores"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --reward 2 \
        --penalty -2 \
        --outfmt 8 | \
    cut -f 11 | \
    grep -qx "20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see known_issues.sh for rewards above 32,767 and penalties below -128


#*****************************************************************************#
#                                                                             #
#                                  valgrind                                   #
#                                                                             #
#*****************************************************************************#

if [[ "${VALGRIND_WORKS}" == "true" ]] ; then
    DB=$(printf ">s1\nAAAACCCCGGGGTTTTACGA\n>s2\nACGTNNNNNACGTRYKM\n" | make_db nucl)
    LOG=$(mktemp)
    printf ">q1\nTCGTAAAACCCCGGGGTTTT\n>q2\nACGTNNNNNACGTRYKM\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" \
            --symtype 0 > /dev/null 2>&1
    DESCRIPTION="valgrind: blastn search (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: blastn search (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG
fi


exit 0
