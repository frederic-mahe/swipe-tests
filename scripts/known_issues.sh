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

## The sanitizer checks below need a binary built with the address
## sanitizer (for instance with: make CXXFLAGS="-g -O1
## -fsanitize=address,undefined" LINKFLAGS="-fsanitize=address,undefined").
## Against a release binary the checks are skipped, not silently
## passed.
SWIPE_HAS_ASAN=false
ASAN_OPTIONS=help=1 "${SWIPE}" -h 2>&1 | \
    grep -q "AddressSanitizer" && SWIPE_HAS_ASAN=true


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

## KI-1: the help message advertises --taxidlist, but the long
## option is named --taxid
DESCRIPTION="KI-1: help message lists --taxidlist"
"${SWIPE}" --help 2> /dev/null | \
    grep -q "^  -x, --taxidlist=FILE" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="KI-1: --taxidlist is rejected"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxidlist <(printf "0\n") 2>&1 | \
    grep -q "unrecognized option '--taxidlist" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-1: --taxid is accepted"
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

## KI-2: --help exits with status 1 (GNU convention is 0)
DESCRIPTION="KI-2: --help exits with status 1"
"${SWIPE}" --help > /dev/null 2>&1
(( $? == 1 )) && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## KI-3: unknown symtype names are parsed with atol() and silently
## select symtype 0 (blastn)
DESCRIPTION="KI-3: --symtype with a misspelled name selects blastn"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype blastpp | \
    grep -qx "Symbol type:       Nucleotide" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-4: the query of tblastx is a nucleotide sequence, but its
## minus strand cannot be selected alone
DESCRIPTION="KI-4: --strand 2 is rejected with tblastx"
DB=$(printf ">s1\nACGTACGTACGT\n" | make_db nucl)
printf ">q1\nACGTACGTACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --strand 2 2>&1 | \
    grep -qx "Illegal strand specified for protein query." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-5: symbol types above 5 get no default gap penalties, so the
## error message is about gap penalties, not the symbol type
DESCRIPTION="KI-5: --symtype 6 reports illegal gap penalties"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 6 2>&1 | \
    grep -qx "Illegal gap penalties." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

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

## KI-7: an expect value of zero (or a non-numerical value, read
## as zero) disables the expect value filter
DESCRIPTION="KI-7: --evalue 0 reports all hits"
DB=$(printf ">s1\nMKVLAAGIVGLLLAW\n>s2\nMKV\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --evalue 0 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-7: --evalue 1e-300 reports no hits"
DB=$(printf ">s1\nMKVLAAGIVGLLLAW\n>s2\nMKV\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --evalue 1e-300 \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-7: --evalue -1 reports all hits"
DB=$(printf ">s1\nMKVLAAGIVGLLLAW\n>s2\nMKV\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --evalue -1 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-8: the output file is opened (and truncated) before the
## other options are checked
DESCRIPTION="KI-8: --out is truncated when another option is invalid"
OUTPUT=$(mktemp)
printf "previous content\n" > "${OUTPUT}"
"${SWIPE}" \
    --out "${OUTPUT}" \
    --outfmt 1 < /dev/null > /dev/null 2>&1
[[ -s "${OUTPUT}" ]] && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
rm -f "${OUTPUT}"
unset OUTPUT

## KI-9: numerical values are not validated (atol and atof)
DESCRIPTION="KI-9: --num_threads 2abc is read as 2"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_threads 2abc | \
    grep -qx "Threads:           2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-9: --dbsize 1e6 is read as 1"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dbsize 1e6 | \
    grep -qx "Effecive db size:  1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                       search engines and score ranges                       #
#                                                                             #
#*****************************************************************************#

## KI-10: with -v 0 and -b 0, the hit list has no room and the
## last entry (index -1) is read
if [[ "${SWIPE_HAS_ASAN}" == "true" ]] ; then
    DESCRIPTION="KI-10: -v 0 -b 0 heap buffer overflow (ASan)"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --num_descriptions 0 \
            --num_alignments 0 2>&1 > /dev/null | \
        grep -q "ERROR: AddressSanitizer: heap-buffer-overflow" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
fi

## KI-11: the 7-bit search engine receives gap penalties as
## 8-bit values: the sum of gap open and gap extension penalties
## wraps around (255 + 1 = 256 = 0), the search score is wrong, and
## the alignment cannot reproduce it
DESCRIPTION="KI-11: --gapopen 255 --gapextend 1 fails (internal error)"
DB=$(printf ">s1\nWWWAWWW\n" | make_db prot)
printf ">q1\nWWWWWW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 255 \
        --gapextend 1 2>&1 > /dev/null | \
    grep -qx "Internal error in align function." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-11: --gapopen 511 --gapextend 1 fails (internal error)"
DB=$(printf ">s1\nWWWAWWW\n" | make_db prot)
printf ">q1\nWWWWWW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 511 \
        --gapextend 1 2>&1 > /dev/null | \
    grep -qx "Internal error in align function." && \
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

## KI-12: scores are stored as 8-bit values for the 7-bit search:
## scores below -128 wrap around, giving wrong scores or an internal
## error when the alignment cannot reproduce the search score
DESCRIPTION="KI-12: matrix score -200 gives a wrong score (56 instead of 20)"
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
    grep -qx "      <score>56</score>" && \
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

DESCRIPTION="KI-12: --penalty -200 fails (internal error)"
DB=$(printf ">s1\nAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nAAAAACAAAAA\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --penalty -200 2>&1 > /dev/null | \
    grep -qx "Internal error in align function." && \
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

## KI-13: scores are stored as 16-bit values for the 16-bit
## search: scores from 32,768 to 65,535 wrap around to negative values
DESCRIPTION="KI-13: --reward 32768 loses a perfect hit"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --reward 32768 \
        --penalty -1 | \
    grep -qx "No hits." && \
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

DESCRIPTION="KI-13: matrix score 40000 loses a perfect hit"
DB=$(printf ">s1\nW\n" | make_db prot)
MATRIX=$(mktemp)
printf "   W\nW  40000\n" > "${MATRIX}"
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


#*****************************************************************************#
#                                                                             #
#                              score matrices                                 #
#                                                                             #
#*****************************************************************************#

## KI-14: a row with fewer scores than columns is accepted, and
## the missing scores take the value of the previous score
DESCRIPTION="KI-14: matrix file, missing score reuses the previous one"
DB=$(printf ">s1\nA\n" | make_db prot)
MATRIX=$(mktemp)
printf "   A  W\nA  5\nW  3 20\n" > "${MATRIX}"
printf ">q1\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix "${MATRIX}" \
        --gapopen 10 \
        --gapextend 1 \
        --outfmt 7 | \
    grep -qx "      <score>5</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${MATRIX}"
remove_db "${DB}"
unset DB MATRIX

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

## KI-16: query lines are read in chunks of 2,047 characters. For
## headers longer than that, the rest of the header is read as
## sequence (here "MKV" at the end of a 2,050-character header)
DESCRIPTION="KI-16: long header spills into the sequence"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">%sMKV\n" "$(printf "%02046d" 0)" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      3 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-16: long header spills into the sequence (hit)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">%sMKV\n" "$(printf "%02046d" 0)" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 3,4 | \
    grep -qx "100.00	3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-17: a '>' at position 2,048 of a sequence line starts a new
## query
DESCRIPTION="KI-17: '>' at position 2,048 of a sequence line starts a query"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n%s>MKV\n" "$(printf "%02047d" 0 | tr "0" "A")" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -c "^Query length:" | \
    grep -qx "2" && \
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

## KI-19: characters are signed, bytes above 0x7f are negative
## indexes in the symbol tables
if [[ "${SWIPE_HAS_ASAN}" == "true" ]] ; then
    DESCRIPTION="KI-19: byte 0xe9 in a query (ASan global-buffer-overflow)"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMK\351V\n" | \
        "${SWIPE}" \
            --db "${DB}" 2>&1 > /dev/null | \
        grep -q "ERROR: AddressSanitizer: global-buffer-overflow" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
fi

## KI-20: only spaces end the query id, tabs are kept
DESCRIPTION="KI-20: a tab in the query header adds a column to TSV output"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\tfoo bar\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    awk -F "\t" '{exit NF == 13 ? 0 : 1}' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-21: carriage returns are not removed from headers
DESCRIPTION="KI-21: CRLF line endings, query id ends with a carriage return"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\r\nMKV\r\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    od -c | \
    grep -q "q   1  \\\\r" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                                  databases                                  #
#                                                                             #
#*****************************************************************************#

## KI-22: PDB identifiers written by recent versions of makeblastdb
## contain a chain-id field (0xA3), unknown to the ASN.1 parser
DESCRIPTION="KI-22: PDB identifiers (fatal ASN.1 parsing error)"
DB=$(printf ">pdb|1ABC|A chain A\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 2>&1 > /dev/null | \
    grep -qx "Error parsing binary ASN.1 in database sequence definition." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-22: PDB identifiers (unexpected object 0xa3)"
DB=$(printf ">pdb|1ABC|A chain A\nMKV\n" | make_db prot -parse_seqids)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null 2>&1 > /dev/null | \
    grep -qx "Unexpected object a3, expected  0." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-23: the size of the index file is not checked: a truncated
## file is read beyond its end (zeros in the last memory page)
DESCRIPTION="KI-23: truncated index file is accepted (empty database)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
head -c 4 "${DB}.pin" > "${DB}.tmp"
mv "${DB}.tmp" "${DB}.pin"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     0 residues in 0 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-23: truncated index file, exit status is 0"
DB=$(printf ">s1\nMKV\n" | make_db prot)
head -c 4 "${DB}.pin" > "${DB}.tmp"
mv "${DB}.tmp" "${DB}.pin"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null 2>&1 && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-24: the dump of a translated database (--symtype 3 or 4)
## prints the translation of the first frame with the nucleotide
## alphabet
DESCRIPTION="KI-24: dump with --symtype 3 prints '#' characters"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
"${SWIPE}" \
    --db "${DB}" \
    --symtype 3 \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "###" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-24: dump with --symtype 4 prints '#' characters"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
"${SWIPE}" \
    --db "${DB}" \
    --symtype 4 \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "###" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-25: taxids are stored in a bitmap of taxid / 8 bytes, and
## negative values are read as huge unsigned values (ASAN_OPTIONS
## makes a sanitizer build behave as a release build)
DESCRIPTION="KI-25: very large taxid (memory allocation fails)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    ASAN_OPTIONS=allocator_may_return_null=1 \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "18446744073709551615\n") 2>&1 | \
    grep -qx "Unable to allocate enough memory." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-25: negative taxid (memory allocation fails)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    ASAN_OPTIONS=allocator_may_return_null=1 \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "%s\n" "-1") 2>&1 | \
    grep -qx "Unable to allocate enough memory." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


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

## KI-27: special characters are not escaped in XML outputs
DESCRIPTION="KI-27: XML, '&' and '<' in descriptions are not escaped"
DB=$(printf ">s1 a&b<c\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <name>lcl|s1 a&b<c</name>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-27: ParAlign XML, '&' and '<' in query descriptions are not escaped"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1 a&b<c\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -q "<queryDescription>q1 a&b<c</queryDescription>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-28: search times are freed before they are printed in the
## ParAlign XML output (printf of a NULL pointer, "(null)" with glibc)
DESCRIPTION="KI-28: ParAlign XML, search start time is (null)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -q "<searchStarted>(null)</searchStarted>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-28: ParAlign XML, search completion time is (null)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -q "<searchCompleted>(null)</searchCompleted>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-29: blastn minus-strand hits are stored with a minus database
## strand, but the ParAlign XML output reads the query strand
DESCRIPTION="KI-29: ParAlign XML, blastn minus-strand hit reported as +"
DB=$(printf ">s1\nAAAAAAAAAAAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nTTTTTTTTTTTTTTTTTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 \
        --outfmt 99 | \
    grep -q "<shortVersionStrand>+</shortVersionStrand>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-29: ParAlign XML, blastn minus-strand hit on same strands"
DB=$(printf ">s1\nAAAAAAAAAAAAAAAAAAAA\n" | make_db nucl)
printf ">q1\nTTTTTTTTTTTTTTTTTTTT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 2 \
        --outfmt 99 | \
    grep -q "<alignmentMatchLocation>Matches on same strands.</alignmentMatchLocation>" && \
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

## KI-30: the ParAlign XML output describes sound queries as
## nucleotide queries, and prints an empty query sequence
DESCRIPTION="KI-30: ParAlign XML, sound query described as nucleotides"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 \
        --outfmt 99 | \
    grep -q "<querySequencetype>Nucleotide</querySequencetype>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-30: ParAlign XML, sound query sequence is empty"
DB=$(printf ">s1\nMKVLAW\n" | make_db prot)
printf ">q1\nLJSKAT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 5 \
        --outfmt 99 | \
    grep -q "<querySequence></querySequence>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-31: ungapped and gapped statistical parameters are the same
## variables in the ParAlign XML output
DESCRIPTION="KI-31: ParAlign XML, ungapped lambda equals gapped lambda"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -E "<(un)?gappedLambda>" | \
    sed 's/.*Lambda>\(.*\)<.*/\1/' | \
    uniq | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-32: the query file name is always prefixed with "./"
DESCRIPTION="KI-32: ParAlign XML, absolute query path is prefixed with ./"
DB=$(printf ">s1\nMKV\n" | make_db prot)
QUERY=$(mktemp)
printf ">q1\nMKV\n" > "${QUERY}"
"${SWIPE}" \
    --db "${DB}" \
    --query "${QUERY}" \
    --outfmt 99 | \
    grep -qF "<queryFilename>.//" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${QUERY}"
remove_db "${DB}"
unset DB QUERY

## KI-33: the search speed is a division by the elapsed time
## (zero for small searches) and by the query length (zero for empty
## queries)
DESCRIPTION="KI-33: speed is infinite for very short searches"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Speed:             inf GCUPS" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="KI-33: speed is not a number for empty queries"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -Eqx "Speed: +-?nan GCUPS" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-34: typo in the parameter block
DESCRIPTION="KI-34: typo \"Effecive\" in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dbsize 100 | \
    grep -q "^Effecive db size:" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## KI-35: the error message for a missing sequence file has an
## extra newline
DESCRIPTION="KI-35: missing .psq file, error message ends with an empty line"
DB=$(printf ">s1\nMKV\n" | make_db prot)
rm -f "${DB}.psq"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    tail -n 1 | \
    grep -qx "" && \
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
