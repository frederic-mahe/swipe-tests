#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="query input (fasta)"
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

## The sanitizer checks below need a binary built with the address
## sanitizer (for instance with: make CXXFLAGS="-g -O1
## -fsanitize=address,undefined" LINKFLAGS="-fsanitize=address,undefined").
## Against a release binary the checks are skipped, not silently
## passed.
SWIPE_HAS_ASAN=false
ASAN_OPTIONS=help=1 "${SWIPE}" -h 2>&1 | \
    grep -q "AddressSanitizer" && SWIPE_HAS_ASAN=true


## the query file is parsed line by line (fgets, 2048-byte buffer):
## - a line starting with '>' starts a new query, the rest of the line
##   is the query description,
## - other lines are sequence lines, each character is mapped to a
##   residue code, characters without a code are silently skipped,
## - queries are searched one after the other, in input order.


#*****************************************************************************#
#                                                                             #
#                                basic format                                 #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="query: a single fasta entry"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: query length is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      4 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: description is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1 some description\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    sed 's/ *$//' | \
    grep -qx "Query description: q1 some description" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: description is padded to 60 characters"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep "^Query description: " | \
    awk '{exit length($0) == 79 ? 0 : 1}' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: long descriptions are wrapped every 60 characters"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">%s\nMKV\n" "$(printf "%0130d" 0)" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -A 2 "^Query description: " | \
    sed 's/ *$//' | \
    awk '{print length($0)}' | \
    tr "\n" " " | \
    grep -qx "79 79 29 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: wrapped description lines are indented"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">%s\nMKV\n" "$(printf "%0130d" 0)" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -A 2 "^Query description: " | \
    tail -n 1 | \
    grep -qx "                   0000000000                                                  " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: sequence can span several lines"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMK\nV\nW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      4 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: very long sequence line (5,000 residues)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n%s\n" "$(printf "%05000d" 0 | tr "0" "M")" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      5000 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: lowercase residues are accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nmkv\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: missing final newline is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      3 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query: empty lines inside a sequence are ignored"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n\nMK\n\nV\n\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      3 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## a header of 2,047 characters (including '>') is read entirely,
## longer headers spill into the sequence (see known_issues.sh)
DESCRIPTION="query: header of 2,047 characters is not truncated"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">%s\nMKV\n" "$(printf "%02046d" 0)" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      3 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                              several queries                                #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="queries: each query is searched"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n>q2\nMKV\n" | \
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

DESCRIPTION="queries: queries are processed in input order"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q2\nMKV\n>q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    tr "\n" " " | \
    grep -qx "q2 q1 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="queries: a query without hits does not stop the search"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nPPP\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx "q2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="queries: the program header is printed once"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -c "^SWIPE " | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="queries: the parameter block is printed for each query"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -c "^Database file:" | \
    grep -qx "2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="queries: query lengths are reported for each query"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n>q2\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep "^Query length:" | \
    tr -s " " | \
    tr "\n" " " | \
    grep -qx "Query length: 3 residues Query length: 4 residues " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="queries: 100 queries"
DB=$(printf ">s1\nMKV\n" | make_db prot)
for ((i = 1 ; i <= 100 ; i++)) ; do
    printf ">q%d\nMKV\n" ${i}
done | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    sort -u | \
    wc -l | \
    grep -qx " *100" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB i


#*****************************************************************************#
#                                                                             #
#                              malformed input                                #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="empty input: exit status is 0"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="empty input: no tabular output"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="empty input: plain output has a program header"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "^SWIPE " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="empty input: plain output has no parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "^Database file:" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the first line is taken as the first sequence line of a query
## without description
DESCRIPTION="missing header: sequence is searched"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "MKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      3 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="missing header: query id is empty in tabular output"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "MKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^	gnl|BL_ORD_ID|0	" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="missing header: no query description is reported"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "MKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "^Query description:" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="missing header: following queries are searched"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "MKV\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    tr "\n" " " | \
    grep -qx " q2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## fasta comment lines (';') are not supported, they are read as
## sequence lines
DESCRIPTION="comment line: ';' lines are parsed as sequence"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ";MKV\n>q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    tr "\n" " " | \
    grep -qx " q1 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="header only: query length is zero"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      0 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="header only: no hits"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="header only: exit status is 0"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="header only: following queries are searched"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx "q2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="header only: speed is not a number"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -Eqx "Speed: +-?nan GCUPS" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="empty header: no query description is reported"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "^Query description:" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="empty header: query is searched"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^	gnl|BL_ORD_ID|0	" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see known_issues.sh for an empty first line
DESCRIPTION="first line made of a space: queries are searched"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf " \n>q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx "q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                         query id and description                            #
#                                                                             #
#*****************************************************************************#

## in tabular and XML outputs, the query is identified by the first
## word of its description (everything before the first space)

DESCRIPTION="query id: first word of the description"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1 some description\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx "q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query id: special characters are kept"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1|a;b=c/d\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx "q1|a;b=c/d" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query id: leading space yields an empty query id"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf "> q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^	gnl|BL_ORD_ID|0	" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## tab characters do not end the query id (see known_issues.sh)
DESCRIPTION="query id: a tab does not end the query id"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\tdescription\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1,2 | \
    grep -qx "q1	description" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="query description: full description in commented tabular output"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1 some description\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 9 | \
    grep -qx "# Query: q1 some description" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## Windows line endings: the carriage return is not removed from the
## header, but is ignored in sequences
DESCRIPTION="CRLF: carriage return is kept in the query id"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\r\nMKV\r\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx $'q1\r' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="CRLF: carriage return is ignored in sequences"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\r\nMK\r\nV\r\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      3 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="CRLF: carriage return is not visible when there is a description"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1 desc\r\nMKV\r\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    grep -qx "q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                           amino acid symbols                                #
#                                                                             #
#*****************************************************************************#

## amino acid queries (--symtype 1, 3 and 5) use the NCBIstdaa
## alphabet: -ABCDEFGHIKLMNPQRSTVWXYZU*OJ (lowercase accepted)

DESCRIPTION="amino acids: 26 letters, '*' and '-' are residues"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nABCDEFGHIJKLMNOPQRSTUVWXYZ*-\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      28 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="amino acids: lowercase letters are residues"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nabcdefghijklmnopqrstuvwxyz\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      26 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="amino acids: digits, spaces, tabs and dots are skipped"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nM1K 2\tV.\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      3 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="amino acids: punctuation is skipped"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nM!K#V?@[]{}~\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      3 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="amino acids: skipped characters do not break the alignment"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nM1K2V3\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 3,4 | \
    grep -qx "100.00	3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## '-' is the gap symbol (code 0) of the NCBIstdaa alphabet
DESCRIPTION="amino acids: '-' is a residue (gap symbol)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMK-V\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Query length:      4 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                           nucleotide symbols                                #
#                                                                             #
#*****************************************************************************#

## nucleotide queries (--symtype 0, 2 and 4) use the NCBI4na
## alphabet: ACGT, U (read as T), and IUPAC ambiguity codes
## BDHKMNRSVWY (lowercase accepted)

DESCRIPTION="nucleotides: ACGTU and ambiguity codes are residues"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGTUBDHKMNRSVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 | \
    grep -qx "Query length:      16 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="nucleotides: lowercase letters are residues"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nacgtubdhkmnrsvwy\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 | \
    grep -qx "Query length:      16 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## X is not a nucleotide symbol, and neither is '-'
DESCRIPTION="nucleotides: other letters, '-', '*' and '.' are skipped"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nAEFIJLOPQXZ-*.\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 | \
    grep -qx "Query length:      1 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="nucleotides: U is read as T"
DB=$(printf ">s1\nACGTACGTACGTACGTACGT\n" | make_db nucl)
printf ">q1\nACGUACGUACGUACGUACGU\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --outfmt 8 | \
    cut -f 3,4 | \
    grep -qx "100.00	20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                           sanitizer checks                                  #
#                                                                             #
#*****************************************************************************#

## see known_issues.sh for bytes above 0x7f

if [[ "${SWIPE_HAS_ASAN}" == "true" ]] ; then
    DESCRIPTION="ASan: multi-line and multi-query input (no error)"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMK\nV\n>q2\n>q3\nMKVW\n" | \
        "${SWIPE}" \
            --db "${DB}" 2>&1 > /dev/null | \
        grep -q "ERROR: AddressSanitizer" && \
        failure "${DESCRIPTION}" || \
            success "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
fi


exit 0
