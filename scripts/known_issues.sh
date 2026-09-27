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

## GitHub #9 (closed in 2014, but the parsing did not change): the
## example of the issue
DESCRIPTION="KI-9: --dbsize 7.06e+06 is read as 7 (GitHub #9)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dbsize 7.06e+06 | \
    grep -qx "Effecive db size:  7" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                       search engines and score ranges                       #
#                                                                             #
#*****************************************************************************#

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

#*****************************************************************************#
#                                                                             #
#                                  databases                                  #
#                                                                             #
#*****************************************************************************#

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
