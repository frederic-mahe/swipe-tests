#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="fixed bugs"
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

## The sanitizer checks below need a binary built with the address
## sanitizer (for instance with: make DEBUG=1). Against a release
## binary the checks are skipped, not silently passed.
SWIPE_HAS_ASAN=false
ASAN_OPTIONS=help=1 "${SWIPE}" -h 2>&1 | \
    grep -q "AddressSanitizer" && SWIPE_HAS_ASAN=true


## Regression tests for the bugs listed in the CHANGES file and in the
## closed GitHub issues (https://github.com/torognes/swipe/issues,
## "GitHub #N" in test descriptions). Tests are sorted by version,
## from the most recent to the oldest.


#*****************************************************************************#
#                                                                             #
#                           2.1.2 (in development)                            #
#                                                                             #
#*****************************************************************************#
##
## Known issues fixed after 2.1.1 (KI-N: see known_issues.sh and the
## file TBD_20260926_potential_issues.md in the swipe repository)


## KI-1: the help message advertised --taxidlist, but the long
## option was named --taxid. --taxidlist is now accepted, and --taxid
## is kept as an alias
DESCRIPTION="KI-1: help message lists --taxidlist"
"${SWIPE}" --help 2> /dev/null | \
    grep -q "^  -x, --taxidlist=FILE" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="KI-1: --taxidlist is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxidlist <(printf "0\n") \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-1: --taxid is accepted (alias of --taxidlist)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "0\n") \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-1: --taxidlist keeps sequences with a listed taxid"
DB=$(printf ">s1\nMKV\n" | make_db prot -parse_seqids -taxid 9606)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxidlist <(printf "9606\n") \
        --outfmt 8 | \
    cut -f 2 | \
    grep -qx "lcl|s1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-1: --taxidlist skips sequences without a listed taxid"
DB=$(printf ">s1\nMKV\n" | make_db prot -parse_seqids -taxid 9606)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxidlist <(printf "10090\n") \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-1: --taxid (alias) skips sequences without a listed taxid"
DB=$(printf ">s1\nMKV\n" | make_db prot -parse_seqids -taxid 9606)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "10090\n") \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-10: with -v 0 and -b 0, the hit list had no room and its last
## entry (index -1) was read
DESCRIPTION="KI-10: -v 0 -b 0 reports no hits"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 0 \
        --num_alignments 0 2> /dev/null | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-10: -v 0 -b 0 exit status is 0"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 0 \
        --num_alignments 0 > /dev/null 2>&1 && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

if [[ "${SWIPE_HAS_ASAN}" == "true" ]] ; then
    DESCRIPTION="KI-10: -v 0 -b 0, no heap buffer overflow (ASan)"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --num_descriptions 0 \
            --num_alignments 0 2>&1 > /dev/null | \
        grep -q "ERROR: AddressSanitizer" && \
        failure "${DESCRIPTION}" || \
            success "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
fi

## KI-11: the 7-bit search engine received gap penalties as 8-bit
## values: the sum of gap open and gap extension penalties wrapped
## around (255 + 1 = 256 = 0), and the search score was wrong or the
## alignment could not reproduce it. Penalties are now clamped to 127
## in the 7-bit engine (exact), and the 63-bit engine uses 64-bit
## penalties
DESCRIPTION="KI-11: --gapopen 255 --gapextend 1 gives the right score (52)"
DB=$(printf ">s1\nWWWAWWW\n" | make_db prot)
printf ">q1\nWWWWWW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 255 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>52</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-11: --gapopen 511 --gapextend 1 gives the right score (52)"
DB=$(printf ">s1\nWWWAWWW\n" | make_db prot)
printf ">q1\nWWWWWW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 511 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>52</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-11: --gapopen 100 --gapextend 1 works (score 52)"
DB=$(printf ">s1\nWWWAWWW\n" | make_db prot)
printf ">q1\nWWWWWW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 100 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>52</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-11: --gapextend 255 gives the right score (52)"
DB=$(printf ">s1\nWWWAWWW\n" | make_db prot)
printf ">q1\nWWWWWW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 1 \
        --gapextend 255 \
        --outfmt 7 | \
    grep -qx "      <score>52</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-11: cheap gaps still win (--gapopen 5 --gapextend 1, score 60)"
DB=$(printf ">s1\nWWWAWWW\n" | make_db prot)
printf ">q1\nWWWWWW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 5 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>60</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-11: gap penalties above 32,767 did not fit in the 16-bit engine;
## it is now skipped (all sequences are aligned by the 63-bit engine)
DESCRIPTION="KI-11: --gapopen 40000 gives the right score (52)"
DB=$(printf ">s1\nWWWAWWW\n" | make_db prot)
printf ">q1\nWWWWWW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 40000 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>52</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-12: scores were stored as 8-bit values for the 7-bit search:
## scores below -128 wrapped around, giving wrong scores or an
## internal error. They are now clamped to -128 in the 7-bit engine
## (exact)
DESCRIPTION="KI-12: matrix score -200 gives the right score (20)"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -200\nW -200 20\n" > "${MATRIX}"
printf ">q1\nWAW\n" | \
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

DESCRIPTION="KI-12: matrix score -100 gives the right score (20)"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5 -100\nW -100 20\n" > "${MATRIX}"
printf ">q1\nWAW\n" | \
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

DESCRIPTION="KI-12: --penalty -200 finds the hit (score 5)"
DB=$(printf ">s1\nAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nAAAAACAAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --penalty -200 \
        --outfmt 7 | \
    grep -qx "      <score>5</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-12: --penalty -128 finds the hit (score 5)"
DB=$(printf ">s1\nAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nAAAAACAAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --penalty -128 \
        --outfmt 7 | \
    grep -qx "      <score>5</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-12: --penalty -32768 finds the hit (score 5)"
DB=$(printf ">s1\nAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nAAAAACAAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --penalty -32768 \
        --outfmt 7 | \
    grep -qx "      <score>5</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-12: --penalty -40000 finds the hit (score 5)"
DB=$(printf ">s1\nAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nAAAAACAAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --penalty -40000 \
        --outfmt 7 | \
    grep -qx "      <score>5</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-13: scores were stored as 16-bit values for the 16-bit search:
## scores from 32,768 to 65,535 wrapped around to negative values, and
## hits were lost. The 16-bit engine is now skipped when a score does
## not fit (all sequences are aligned by the 63-bit engine)
DESCRIPTION="KI-13: --reward 32768 finds a perfect hit"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --reward 32768 \
        --penalty -1 \
        --outfmt 7 | \
    grep -qx "      <score>327680</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-13: --reward 32767 finds a perfect hit"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --reward 32767 \
        --penalty -1 \
        --outfmt 7 | \
    grep -qx "      <score>327670</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-13: --reward 65535 finds a perfect hit"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --reward 65535 \
        --penalty -1 \
        --outfmt 7 | \
    grep -qx "      <score>655350</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-13: --reward 70000 finds a perfect hit"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --reward 70000 \
        --penalty -1 \
        --outfmt 7 | \
    grep -qx "      <score>700000</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-13: matrix score 40000 finds a perfect hit"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   W\nW  40000\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>40000</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

## KI-16: query lines were read in chunks of 2,047 characters, and
## the rest of a longer header was read as sequence
DESCRIPTION="KI-16: long header does not spill into the sequence"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">%sMKV\n" "$(printf "%02046d" 0)" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      0 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-16: long header does not spill into the sequence (no hit)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">%sMKV\n" "$(printf "%02046d" 0)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-16: query id of 3,000 characters is reported whole"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">%s\nMKV\n" "$(printf "%03000d" 0)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx "$(printf "%03000d" 0)" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-17: a '>' at position 2,048 of a sequence line started a new
## query
DESCRIPTION="KI-17: '>' at position 2,048 of a sequence line is skipped"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n%s>MKV\n" "$(printf "%02047d" 0 | tr "0" "A")" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep "^Query length:" | \
    tr "\n" " " | \
    grep -qx "Query length:      2050 residues " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-17: '>' elsewhere in a sequence line is skipped"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n%s>MKV\n" "$(printf "%02046d" 0 | tr "0" "A")" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -c "^Query length:" | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-21: carriage returns were not removed from headers
DESCRIPTION="KI-21: CRLF line endings, query id has no carriage return"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\r\nMKV\r\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx "q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-21: CRLF line endings, description has no carriage return"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1 desc\r\nMKV\r\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 9 | \
    grep -qx "# Query: q1 desc" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-21: CRLF line endings, empty first line is skipped"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "\r\n>q1\r\nMKV\r\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx "q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-18: an empty first line was read as an empty query, and the
## rest of the query file was silently ignored
DESCRIPTION="KI-18: empty first line, all queries are searched"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "\n>q1\nMKV\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    tr "\n" " " | \
    grep -qx "q1 q2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-18: empty first line, no empty query is reported"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "\n>q1\nMKV\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep "^Query length:" | \
    tr "\n" " " | \
    grep -qx "Query length:      3 residues Query length:      3 residues " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-18: several empty first lines, all queries are searched"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "\n\n\n>q1\nMKV\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    tr "\n" " " | \
    grep -qx "q1 q2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-18: a query file made of an empty line has no query"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "^Query length:" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-18: empty first line, exit status is 0"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "\n>q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


## KI-19: characters are signed, and bytes above 0x7f were negative
## indexes in the symbol tables (query and score matrix readers)
DESCRIPTION="KI-19: byte 0xe9 in a query is skipped"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMK\351V\n" | \
    "${SWIPE}" \
        --db "${DB}" 2> /dev/null | \
    grep -qx "Query length:      3 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-19: byte 0xe9 in a score matrix file is ignored"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W \351\nA  5 -3 1\nW -3 20 1\n\351 1 1 1\n" > "${MATRIX}"
printf ">q1\nWAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 2> /dev/null | \
    grep -qx "      <score>20</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

if [[ "${SWIPE_HAS_ASAN}" == "true" ]] ; then
    DESCRIPTION="KI-19: byte 0xe9 in a query, no out-of-bounds read (ASan)"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMK\351V\n" | \
        "${SWIPE}" \
            --db "${DB}" 2>&1 > /dev/null | \
        grep -q "ERROR: AddressSanitizer" && \
        failure "${DESCRIPTION}" || \
            success "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB

    DESCRIPTION="KI-19: byte 0xe9 in a score matrix file, no out-of-bounds read (ASan)"
    DB=$(printf ">s1\nW\n" | make_db prot)
    MATRIX=$(mktemp)
    printf "   A  W \351\nA  5 -3 1\nW -3 20 1\n\351 1 1 1\n" > "${MATRIX}"
    printf ">q1\nWAW\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --matrix "${MATRIX}" \
            --gapopen 10 \
            --gapextend 1 \
            --outfmt 7 2>&1 > /dev/null | \
        grep -q "ERROR: AddressSanitizer" && \
        failure "${DESCRIPTION}" || \
            success "${DESCRIPTION}"
    rm -f "${MATRIX}"
    remove_db "${DB}"
    unset DB MATRIX
fi

## KI-22: PDB identifiers written by recent versions of makeblastdb
## contain a chain-id field (0xA3), unknown to the ASN.1 parser (fatal
## error). The chain-id is now read, and shown as is (as by BLAST+)
DESCRIPTION="KI-22: PDB identifiers, search succeeds"
DB=$(printf ">pdb|1ABC|A chain A\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 > /dev/null 2>&1 && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-22: PDB identifiers, tabular output shows the PDB id"
DB=$(printf ">pdb|1ABC|A chain A\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 2 | \
    grep -qx "pdb|1ABC|A" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-22: PDB identifiers, dump shows the PDB id and the title"
DB=$(printf ">pdb|1ABC|A chain A\nMKV\n" | make_db prot -parse_seqids)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    head -n 1 | \
    grep -qx ">pdb|1ABC|A chain A" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-22: PDB identifiers, lowercase chain is shown as is"
DB=$(printf ">pdb|2DEF|b chain b\nMKV\n" | make_db prot -parse_seqids)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    head -n 1 | \
    grep -qx ">pdb|2DEF|b chain b" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-22: PDB identifiers, multi-character chains are shown as is"
DB=$(printf ">pdb|3GHI|AA chain AA\nMKV\n>pdb|4JKL|Lb chain Lb\nMKV\n" | make_db prot -parse_seqids)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    grep ">" | \
    tr "\n" " " | \
    grep -qx ">pdb|3GHI|AA chain AA >pdb|4JKL|Lb chain Lb " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-22: PDB identifiers, plain output shows the PDB id"
DB=$(printf ">pdb|1ABC|A chain A\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "^>pdb|1ABC|A chain A" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-24: the dump of a translated database (--symtype 3 or 4)
## printed the translation of the first frame with the nucleotide
## alphabet ('###'). The nucleotide sequence is now dumped
DESCRIPTION="KI-24: dump with --symtype 3 prints the nucleotide sequence"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
"${SWIPE}" \
    --db "${DB}" \
    --symtype 3 \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "ACGTACGTAC" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-24: dump with --symtype 4 prints the nucleotide sequence"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
"${SWIPE}" \
    --db "${DB}" \
    --symtype 4 \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "ACGTACGTAC" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-24: dumps with --symtype 0, 3 and 4 are identical (ambiguous nucleotides)"
DB=$(printf ">s1\nACGTACGTAC\n>s2\nACGTNNRYACGTTTGA\n" | make_db nucl)
DUMP0=$("${SWIPE}" --db "${DB}" --symtype 0 --dump 1 < /dev/null)
DUMP3=$("${SWIPE}" --db "${DB}" --symtype 3 --dump 1 < /dev/null)
DUMP4=$("${SWIPE}" --db "${DB}" --symtype 4 --dump 1 < /dev/null)
[[ "${DUMP0}" == "${DUMP3}" && "${DUMP0}" == "${DUMP4}" ]] && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB DUMP0 DUMP3 DUMP4

## KI-27: special characters (& < > " ') were not escaped in XML
## outputs
DESCRIPTION="KI-27: XML, '&' and '<' in database descriptions are escaped"
DB=$(printf ">s1 a&b<c\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <name>lcl|s1 a&amp;b&lt;c</name>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-27: XML, quotes and '>' in database descriptions are escaped"
DB=$(printf ">s1 5'-3' \"x\" y>z\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <name>lcl|s1 5&apos;-3&apos; &quot;x&quot; y&gt;z</name>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-27: XML, '&' in the query id is escaped"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1&x\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <query>q1&amp;x</query>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-27: ParAlign XML, '&' and '<' in query descriptions are escaped"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1 a&b<c\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -q "<queryDescription>q1 a&amp;b&lt;c</queryDescription>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-27: ParAlign XML, '&' in database descriptions is escaped"
DB=$(printf ">s1 a&b\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -q "<longVersionName>s1 a&amp;b</longVersionName>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-27: ParAlign XML, short names are truncated to 35 characters before escaping"
DB=$(printf ">s1 %s&b\nMKV\n" "$(printf "%031d" 0)" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -q "<shortVersionName>s1 $(printf "%031d" 0)&amp;</shortVersionName>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-27: ParAlign XML, '&' in the database title is escaped"
DB_DIR=$(mktemp -d)
printf ">s1\nMKV\n" | \
    makeblastdb \
        -dbtype prot \
        -blastdb_version 4 \
        -in - \
        -title "a&b" \
        -out "${DB_DIR}/db" > /dev/null 2>&1
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB_DIR}/db" \
        --outfmt 99 | \
    grep -q "<databaseDescription>a&amp;b</databaseDescription>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${DB_DIR}"
unset DB_DIR

## KI-28: search times were freed before they were printed in the
## ParAlign XML output (printf of a NULL pointer, "(null)" with glibc)
DESCRIPTION="KI-28: ParAlign XML, search start time is a date"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -Eq "<searchStarted>[A-Z][a-z]{2}, [ 0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} UTC</searchStarted>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-28: ParAlign XML, search completion time is a date"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -Eq "<searchCompleted>[A-Z][a-z]{2}, [ 0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} UTC</searchCompleted>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-28: ParAlign XML, search times are shown for every query"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -c "<searchStarted>[A-Z]" | \
    grep -qx "2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-29: blastn minus-strand hits are stored with a minus database
## strand, but the ParAlign XML output read the query strand
DESCRIPTION="KI-29: ParAlign XML, blastn minus-strand hit reported as -"
DB=$(printf ">s1\nAAAAAAAAAAAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nTTTTTTTTTTTTTTTTTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 \
        --outfmt 99 | \
    grep -q "<shortVersionStrand>-</shortVersionStrand>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-29: ParAlign XML, blastn minus-strand hit on complementary strands"
DB=$(printf ">s1\nAAAAAAAAAAAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nTTTTTTTTTTTTTTTTTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 \
        --outfmt 99 | \
    grep -q "<alignmentMatchLocation>Matches on complementary strands.</alignmentMatchLocation>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-29: plain output, same blastn hit is on the minus strand"
DB=$(printf ">s1\nAAAAAAAAAAAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nTTTTTTTTTTTTTTTTTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 | \
    grep -qx " Strand = Plus / Minus" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-29: ParAlign XML, blastn plus-strand hit reported as +"
DB=$(printf ">s1\nAAAAAAAAAAAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nAAAAAAAAAAAAAAAAAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 99 | \
    grep -q "<shortVersionStrand>+</shortVersionStrand>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-29: ParAlign XML, blastn hits on both strands have distinct anchors"
DB=$(printf ">s1\nACGTACGT\n" | make_db nucl)
printf ">q1\nACGTACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --outfmt 99 | \
    grep "<shortVersionAnchor>" | \
    sort -u | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-37: with --outfmt 7, hits shown without an alignment (beyond
## --num_alignments) reported an uninitialized <len> (0, a stale
## value, or garbage)
DESCRIPTION="KI-37: --outfmt 7, hit without alignment reports its length"
DB=$(printf ">s1\nMKVLL\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 1 \
        --num_alignments 0 \
        --outfmt 7 | \
    grep -qx "      <len>5</len>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-37: --outfmt 7, hits with and without alignment report their lengths"
DB=$(printf ">s1\nMKVLL\n>s2\nMKVAAA\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 2 \
        --num_alignments 1 \
        --outfmt 7 | \
    grep "<len>" | \
    tr -d " \n" | \
    grep -qx "<len>6</len><len>5</len>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-37: --outfmt 7, blastn hit without alignment reports its length"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --num_descriptions 1 \
        --num_alignments 0 \
        --outfmt 7 | \
    grep -qx "      <len>10</len>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-38: strings of the binary ASN.1 headers are read into a buffer
## of 2,048 bytes; a string of 2,048 characters or more filled it,
## and the terminating null byte was written one byte past its end
## (then copied with strcpy into fields of the same size). Outputs
## were not affected (titles longer than 2,048 characters are still
## truncated, see database.sh). The overflow stays inside a structure,
## ASan misses it: the check relies on UBSan (make DEBUG=1)
if [[ "${SWIPE_HAS_ASAN}" == "true" ]] ; then
    DESCRIPTION="KI-38: title of 2,048 characters, no out-of-bounds index (UBSan)"
    DB=$(printf ">s1 %s\nMKV\n" "$(printf "%02045d" 0)" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" 2>&1 > /dev/null | \
        grep -q "runtime error: index" && \
        failure "${DESCRIPTION}" || \
            success "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB

    DESCRIPTION="KI-38: title of 5,000 characters, dump, no out-of-bounds index (UBSan)"
    DB=$(printf ">sp|P12345|NAME_HUMAN %s\nMKV\n" "$(printf "%05000d" 0)" | make_db prot -parse_seqids)
    "${SWIPE}" \
        --db "${DB}" \
        --dump 1 2>&1 < /dev/null > /dev/null | \
        grep -q "runtime error: index" && \
        failure "${DESCRIPTION}" || \
            success "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
fi


#*****************************************************************************#
#                                                                             #
#      2.1.1 (2021-06-28): fix for very long header strings in databases      #
#                                                                             #
#*****************************************************************************#
##
## https://github.com/torognes/swipe/commit/314123b8ce5339dd3952e541678e5f848c6b2487
##
## Header strings are encoded in binary ASN.1. Their length is stored
## in one byte (< 128), or in 1, 2, 3 or 4 extra bytes (0x81, 0x82,
## 0x83, 0x84). Before 2.1.1, lengths encoded with 3 or 4 bytes (>
## 65,535 characters) were rejected: "Error: illegal string length
## (83)." and "Error parsing binary ASN.1 in database sequence
## definition."

DESCRIPTION="2.1.1: header of 130 characters (length encoded with 0x81)"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%0130d" 0)" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.1.1: header of 300 characters (length encoded with 0x82)"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%0300d" 0)" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.1.1: header of 65,000 characters (length encoded with 0x82)"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%065000d" 0)" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the query id is printed before the subject header is parsed:
## check the whole line
DESCRIPTION="2.1.1: header of 70,000 characters (length encoded with 0x83)"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%070000d" 0)" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1	gnl|BL_ORD_ID|0	100.00	3	" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.1.1: header of 70,000 characters (no parsing error)"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%070000d" 0)" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 2>&1 > /dev/null | \
    grep -q "illegal string length" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.1.1: header of 70,000 characters (dump)"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%070000d" 0)" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "MKV" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.1.1: header of 70,000 characters (following sequence)"
DB=$(printf ">s1 %s\nMKV\n>s2\nMKVW\n" "$(printf "%070000d" 0)" | make_db prot -parse_seqids)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    head -n 1 | \
    cut -f 2 | \
    grep -qx "lcl|s2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## more than 16,777,215 characters (a 16 MB header)
DESCRIPTION="2.1.1: header of 16,777,300 characters (length encoded with 0x84)"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%016777300d" 0)" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1	gnl|BL_ORD_ID|0	100.00	3	" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                        2.1.0 (2018-05-04)                                   #
#                                                                             #
#*****************************************************************************#

## - Fix for changes to NCBI database format
DESCRIPTION="2.1.0: databases made by current makeblastdb (-blastdb_version 4)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1	gnl|BL_ORD_ID|0	" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.1.0: databases made by current makeblastdb (-parse_seqids)"
DB=$(printf ">sp|P12345|NAME_HUMAN desc\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1	sp|P12345|NAME_HUMAN	" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## - Added query description to XML output
DESCRIPTION="2.1.0: query description in XML output"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1 desc\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <query>q1</query>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## - Fixed compilation errors with C++11: not testable


#*****************************************************************************#
#                                                                             #
#                        2.0.12 (2015-12-18)                                  #
#                                                                             #
#*****************************************************************************#

## - Fixed a bug in memory allocation that caused segfaults.
## - Fixed a minor memory leak.
if [[ "${VALGRIND_WORKS}" == "true" ]] ; then
    DB=$(for ((i = 1 ; i <= 50 ; i++)) ; do
             printf ">s%d\nMKV%sW\n" ${i} "$(repeat A $(( i % 7 )))"
         done | make_db prot)
    LOG=$(mktemp)
    printf ">q1\nMKVAAAW\n>q2\nMKVW\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" \
            --num_threads 4 > /dev/null 2>&1
    DESCRIPTION="2.0.12: no memory leak (4 threads, 2 queries)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="2.0.12: no memory errors (4 threads, 2 queries)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG i
fi

## GitHub #28: crash when searching nucleotide sequences (fixed in
## 2.0.12). A local variable shadowed the global maxchunksize, and
## the lists of the alignment threads were allocated too small: two
## database sequences searched on both strands corrupted the heap
DESCRIPTION="2.0.12 (GitHub #28): blastn, 2 subjects, both strands (4 hits)"
DB=$(printf ">s1\nACGTACGTTGCAA\n>s2\nACGTACGTTGCAAA\n" | make_db nucl)
printf ">q1\nACGTACGTTGCA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *4" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                        2.0.11 (2014-06-27)                                  #
#                                                                             #
#*****************************************************************************#

## - Resolved a bug that resulted in SWIPE terminating with a fatal
##   internal error in the align function. After recomputing an
##   alignment score > 32768 with 16-bit magnitude, a subsequent
##   16-bit score computation could be wrong.
DESCRIPTION="2.0.11: score above 32,768 followed by 16-bit scores (no error)"
DB=$(printf ">s1\n%s\n>s2\n%s\n>s3\n%s\n" \
            "$(repeat W 3000)" "$(repeat W 1500)" "$(repeat W 200)" | make_db prot)
printf ">q1\n%s\n" "$(repeat W 3000)" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null 2>&1 && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.0.11: score above 32,768 followed by 16-bit scores (scores)"
DB=$(printf ">s1\n%s\n>s2\n%s\n>s3\n%s\n" \
            "$(repeat W 3000)" "$(repeat W 1500)" "$(repeat W 200)" | make_db prot)
printf ">q1\n%s\n" "$(repeat W 3000)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep "<score>" | \
    tr -d " " | \
    tr "\n" " " | \
    grep -qx "<score>33000</score> <score>16500</score> <score>2200</score> " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.0.11: score above 32,768 followed by 16-bit scores (alignments)"
DB=$(printf ">s1\n%s\n>s2\n%s\n>s3\n%s\n" \
            "$(repeat W 3000)" "$(repeat W 1500)" "$(repeat W 200)" | make_db prot)
printf ">q1\n%s\n" "$(repeat W 3000)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep "<alignment>" | \
    tr -d " " | \
    tr "\n" " " | \
    grep -qx "<alignment>M3000</alignment> <alignment>M1500</alignment> <alignment>M200</alignment> " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## - Reduced memory usage when a the number of alignments or results
##   asked for using the -b and -v options was higher than the
##   possible maximum number.
DESCRIPTION="2.0.11: very large -v and -b values are accepted"
DB=$(printf ">s1\nMKV\n>s2\nMKVW\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 2000000000 \
        --num_alignments 2000000000 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## GitHub #16: segmentation fault with large nucleotide databases
## when many alignments are asked for (-b 1000000), fixed in 2.0.11:
## memory for hits is now limited by the number of database
## sequences. Plus strand only: on both strands, versions before
## 2.0.12 also hit GitHub #28
DESCRIPTION="2.0.11 (GitHub #16): blastn, 100 subjects with -v and -b 2,000,000,000"
DB=$(for ((i = 1 ; i <= 100 ; i++)) ; do
         printf ">s%d\nACGTACGTTGCA%s\n" ${i} "$(repeat A $(( i % 13 )))"
     done | make_db nucl)
printf ">q1\nACGTACGTTGCA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --num_descriptions 2000000000 \
        --num_alignments 2000000000 \
        --outfmt 8 | \
    cut -f 2 | \
    sort -u | \
    wc -l | \
    grep -qx " *100" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i

## GitHub #26: after a score above 32,768 in a channel of the 16-bit
## engine, the next sequence in that channel was not fully reset:
## M (-32,768) was added once, and cells above 32,768 kept their
## excess (fixed in 2.0.11: M is added twice). The next score was too
## large, and computing its alignment ended with "Internal error in
## align function". Here, s0 scores 33,000 (3,000 W): the last cells
## of its column keep up to 232. The 16 other sequences have the same
## length (one of them follows s0 in its channel) and start with 20 W
## (score 220) that inherit that excess
DESCRIPTION="2.0.11 (GitHub #26): 16-bit channel reset after a score above 32,768"
DB=$( (printf ">s0\n%s\n" "$(repeat W 3000)"
       for ((i = 1 ; i <= 16 ; i++)) ; do
           printf ">s%d\n%s%s\n" ${i} "$(repeat W 20)" "$(repeat P 2980)"
       done) | make_db prot)
printf ">q1\n%s\n" "$(repeat W 3000)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -cx "      <score>220</score>" | \
    grep -qx "16" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i


#*****************************************************************************#
#                                                                             #
#                        2.0.10 (2014-06-25)                                  #
#                                                                             #
#*****************************************************************************#

## - Resolved an inconsistency in SWIPE with custom non-symmetric
##   matrices. This problem could result in SWIPE terminating with a
##   fatal internal error in the align function.
MATRIX=$(mktemp)
printf "   A  W  K  M\nA  4 -9  1 -2\nW  3 11 -5  2\nK -7  2  5 -1\nM  1 -3  2  5\n" > "${MATRIX}"
for QUERY in AWKMAWKM WWAKKM MMMWAAKK KAWMKAWM ; do
    DESCRIPTION="2.0.10: non-symmetric matrix, query ${QUERY} (no error)"
    DB=$(printf ">s1\nAWKMAWKM\n>s2\nWAKWMA\n>s3\nKKMMWWAA\n>s4\nAAWWKKMM\n" | make_db prot)
    printf ">q1\n%s\n" "${QUERY}" | \
        "${SWIPE}" \
            --db "${DB}" \
            --matrix "${MATRIX}" \
            --gapopen 3 \
            --gapextend 1 > /dev/null 2>&1 && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
rm -f "${MATRIX}"
unset MATRIX QUERY


#*****************************************************************************#
#                                                                             #
#                        2.0.9 (2014-01-21)                                   #
#                                                                             #
#*****************************************************************************#

## - Improved detection of CPU features (SSSE3 etc) and added
##   alternative code for the search7 function for CPUs with and
##   without SSSE3: not testable (depends on the CPU)

## - Fixed an inconsistency in the counting of 'positives', i.e.
##   similar but non-identical residues
DESCRIPTION="2.0.9: positives in plain output (identities and similar residues)"
DB=$(printf ">s1\nMKVWMKVWIL\n" | make_db prot)
printf ">q1\nMKIWMKVWLI\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx " Identities = 7/10 (70%), Positives = 10/10 (100%)" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.0.9: positives in ParAlign XML output"
DB=$(printf ">s1\nMKVWMKVWIL\n" | make_db prot)
printf ">q1\nMKIWMKVWLI\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -q "<positiveNominator>10</positiveNominator>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.0.9: positives in simple XML output"
DB=$(printf ">s1\nMKVWMKVWIL\n" | make_db prot)
printf ">q1\nMKIWMKVWLI\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <aseq>||+|||||++</aseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                        2.0.8 (2014-01-17)                                   #
#                                                                             #
#*****************************************************************************#

## - Removed a bug in computation of the score of alignments with a
##   score higher than 32767
DESCRIPTION="2.0.8: score higher than 32,767 (3,000 W = 33,000)"
DB=$(printf ">s1\n%s\n" "$(repeat W 3000)" | make_db prot)
printf ">q1\n%s\n" "$(repeat W 3000)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>33000</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## - Removed a bug in computation of the alignment of sequences that
##   scored higher than 65535
DESCRIPTION="2.0.8: alignment of sequences scoring higher than 65,535"
DB=$(printf ">s1\n%s\n" "$(repeat W 6000)" | make_db prot)
printf ">q1\n%sPPPP%s\n" "$(repeat W 3000)" "$(repeat W 3000)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <alignment>M3000D4M3000</alignment>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.0.8: score of a gapped alignment higher than 65,535"
DB=$(printf ">s1\n%s\n" "$(repeat W 6000)" | make_db prot)
printf ">q1\n%sPPPP%s\n" "$(repeat W 3000)" "$(repeat W 3000)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>65985</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## GitHub #10: no similarity was reported for the self-alignment of
## long proteins (about 6,800 aa) as soon as the score reached 2^15
## (fixed in 2.0.8). Here, the 20 amino acids are repeated 350 times
## (sum of the BLOSUM62 diagonal: 116, 350 x 116 = 40,600)
DESCRIPTION="2.0.8 (GitHub #10): self-hit of a 7,000 aa protein (score 40,600)"
QUERY=$(repeat ACDEFGHIKLMNPQRSTVWY 350)
DB=$(printf ">s1\n%s\n" "${QUERY}" | make_db prot)
printf ">q1\n%s\n" "${QUERY}" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>40600</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB QUERY

## GitHub #3: "Internal error in align function", seen when a long
## protein was compared to itself (score 65,542), fixed in 2.0.8.
## Self-hits scoring around 2^15 and 2^16 (W/W = 11, A/A = 4, W/A = -3):
## number of W, number of A, expected score
for SCORES in "2977 5 32767" "2976 8 32768" "2975 11 32769" \
              "5957 2 65535" "5956 5 65536" "5954 12 65542" ; do
    read -r W_COUNT A_COUNT SCORE <<< "${SCORES}"
    DESCRIPTION="2.0.8 (GitHub #3): self-hit scoring ${SCORE} (${W_COUNT} W, ${A_COUNT} A)"
    QUERY="$(repeat W "${W_COUNT}")$(repeat A "${A_COUNT}")"
    DB=$(printf ">s1\n%s\n" "${QUERY}" | make_db prot)
    printf ">q1\n%s\n" "${QUERY}" | \
        "${SWIPE}" \
            --db "${DB}" \
            --outfmt 7 | \
        grep -qx "      <score>${SCORE}</score>" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB QUERY
done
unset SCORES W_COUNT A_COUNT SCORE


#*****************************************************************************#
#                                                                             #
#                        2.0.7 (2013-05-02)                                   #
#                                                                             #
#*****************************************************************************#

## - Removed a few memory leaks discovered with Valgrind
if [[ "${VALGRIND_WORKS}" == "true" ]] ; then
    DB=$(printf ">s1\nACGTTGCAAGGCTTAACCGT\n>s2\nAAAACCCCGGGGTTTT\n" | make_db nucl)
    LOG=$(mktemp)
    printf ">q1\nACGTTGCAAGGCTTAACCGT\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" \
            --symtype 4 \
            --outfmt 99 > /dev/null 2>&1
    DESCRIPTION="2.0.7: no memory leak (tblastx, ParAlign XML)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG
fi


#*****************************************************************************#
#                                                                             #
#                        2.0.6 (2013-05-01)                                   #
#                                                                             #
#*****************************************************************************#

## - Increased size of buffers for deflines
DESCRIPTION="2.0.6: deflines of 2,000 characters"
DB=$(printf ">sp|P12345|NAME_HUMAN %s\nMKV\n" "$(printf "%02000d" 0)" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep "<name>" | \
    awk '{exit length($0) == 2040 ? 0 : 1}' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## - Added option (-z) to set effective length of the database
DESCRIPTION="2.0.6: -z sets the effective length of the database"
DB=$(printf ">s1\nMKVLAAGIVGLLLAW\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -z 1000000 | \
    grep -qx "Effecive db size:  1000000" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## GitHub #4: swipe crashed on some of NCBI's preformatted databases,
## e.g. nr ("probably fixed in SWIPE 2.0.6"). Before 2.0.6, the buffers
## for sequence titles had 2,048 bytes: a longer title, as found in
## nr, ended with a segmentation fault (see database.sh for the
## truncation of long titles)
DESCRIPTION="2.0.6 (GitHub #4): title of 3,000 characters (no crash)"
DB=$(printf ">sp|P12345|NAME_HUMAN %s\nMKV\n" "$(printf "%03000d" 0)" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1	sp|P12345|NAME_HUMAN	100.00	3	" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## - Minor typo in help text corrected: not testable


#*****************************************************************************#
#                                                                             #
#                        2.0.5 (2012-08-09)                                   #
#                                                                             #
#*****************************************************************************#

## - Added option (-H) to show taxid and membership/link bits
DESCRIPTION="2.0.5: -H shows taxids"
DB=$(printf ">s1\nMKV\n" | make_db prot -parse_seqids -taxid 9606)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -H \
        --outfmt 8 | \
    cut -f 2 | \
    grep -qx "lcl|s1|taxid|9606" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                        2.0.4 (2012-07-04)                                   #
#                                                                             #
#*****************************************************************************#

## - Fixed display of header lines with TSV format (-m 9)
DESCRIPTION="2.0.4: -m 9 header lines"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1 desc\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -m 9 | \
    grep "^# " | \
    cut -d " " -f 2 | \
    tr "\n" " " | \
    grep -qx "SWIPE Query: Database: Fields: " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                        2.0.3 (2012-06-11)                                   #
#                                                                             #
#*****************************************************************************#

## - Fixed bug with option "-c" not being allowed
DESCRIPTION="2.0.3: -c is allowed"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -c 10 | \
    grep -qx "Min score shown:   10" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                        2.0.2 (2012-06-08)                                   #
#                                                                             #
#*****************************************************************************#

## - Fixed bug relating to amino acids symbols "JOU*" on non-SSSE3
##   cpus (the SSSE3 code path is tested here, see 2.0.9)
while read -r SYMBOL SCORE ; do
    DESCRIPTION="2.0.2: amino acid symbol ${SYMBOL} (WW${SYMBOL}WW = ${SCORE})"
    DB=$(printf ">s1\nWW%sWW\n" "${SYMBOL}" | make_db prot)
    printf ">q1\nWW%sWW\n" "${SYMBOL}" | \
        "${SWIPE}" \
            --db "${DB}" \
            --outfmt 7 | \
        grep -qx "      <score>${SCORE}</score>" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
J 47
O 43
U 43
* 45
EOF
unset SYMBOL SCORE

## - Minor output format changes / bug fixes: not testable


#*****************************************************************************#
#                                                                             #
#                        2.0.1 (2012-02-24)                                   #
#                                                                             #
#*****************************************************************************#

## - hits.cc: Fixed bug in display of alignment coordinates in XML and
##   TSV formats
DESCRIPTION="2.0.1: alignment coordinates in XML format (query)"
DB=$(printf ">s1\nPPPPPMKVWPPPPP\n" | make_db prot)
printf ">q1\nAAMKVWAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <qpos>3,6</qpos>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.0.1: alignment coordinates in XML format (subject)"
DB=$(printf ">s1\nPPPPPMKVWPPPPP\n" | make_db prot)
printf ">q1\nAAMKVWAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <dpos>6,9</dpos>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="2.0.1: alignment coordinates in TSV format"
DB=$(printf ">s1\nPPPPPMKVWPPPPP\n" | make_db prot)
printf ">q1\nAAMKVWAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 7-10 | \
    grep -qx "3	6	6	9" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


exit 0
