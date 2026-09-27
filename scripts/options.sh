#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="command-line options"
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

DESCRIPTION="make_db creates a database version 4"
DB=$(printf ">s1\nMKV\n" | make_db prot)
[[ -s "${DB}.pin" && -s "${DB}.phr" && -s "${DB}.psq" ]] && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


## swipe 2.1.1
## the valid options are (help message):
## -h, --help                 show help
## -d, --db=FILE              sequence database base name (required)
## -i, --query=FILE           query sequence filename (stdin)
## -M, --matrix=NAME/FILE     score matrix name or filename (BLOSUM62)
## -q, --penalty=NUM          penalty for nucleotide mismatch (-3)
## -r, --reward=NUM           reward for nucleotide match (1)
## -G, --gapopen=NUM          gap open penalty (11)
## -E, --gapextend=NUM        gap extension penalty (1)
## -v, --num_descriptions=NUM sequence descriptions to show (250)
## -b, --num_alignments=NUM   sequence alignments to show (100)
## -e, --evalue=REAL          maximum expect value of sequences to show (10.0)
## -k, --minevalue=REAL       minimum expect value of sequences to show (0.0)
## -c, --min_score=NUM        minimum score of sequences to show (1)
## -u, --max_score=NUM        maximum score of sequences to show (inf.)
## -a, --num_threads=NUM      number of threads to use [1-256] (1)
## -m, --outfmt=NUM           output format [0,7-9=plain,xml,tsv,tsv+] (0)
## -I, --show_gis             show gi numbers in results (no)
## -p, --symtype=NAME/NUM     symbol type/translation [0-4] (1)
## -S, --strand=NAME/NUM      query strands to search [1-3] (3)
## -Q, --query_gencode=NUM    query genetic code [1-23] (1)
## -D, --db_gencode=NUM       database genetic code [1-23] (1)
## -x, --taxidlist=FILE       taxid list filename (none)
## -N, --dump=NUM             dump database [0-2=no,yes,split headers] (0)
## -H, --show_taxid           show taxid etc in results (no)
## -o, --out=FILE             output file (stdout)
## -z, --dbsize=NUM           set effective database size (0)
##
## undocumented options: -C (--comp_based_stats), -F (--filter), -K
## (--subalignments), -p 5 (--symtype sound), -m 99 (ParAlign XML)
##
## the parameter block printed at the beginning of the default
## output (-m 0) is used below to check the value of each option


#*****************************************************************************#
#                                                                             #
#                                    help                                     #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="-h prints a help message"
"${SWIPE}" -h 2> /dev/null | \
    grep -q "^Usage: " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="--help prints a help message"
"${SWIPE}" --help 2> /dev/null | \
    grep -q "^Usage: " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## GNU convention is to exit with status 0 after --help
DESCRIPTION="--help exits with status 1 (not 0)"
"${SWIPE}" --help > /dev/null 2>&1
(( $? == 1 )) && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="--help message is written to stdout"
"${SWIPE}" --help 2> /dev/null | \
    grep -q "." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="--help writes nothing to stderr"
"${SWIPE}" --help 2>&1 > /dev/null | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"

DESCRIPTION="--help message starts with the program name and version (no build date)"
"${SWIPE}" --help 2> /dev/null | \
    head -n 1 | \
    grep -Eqx "SWIPE [0-9]+[.][0-9]+[.][0-9]+" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="--help message contains the reference"
"${SWIPE}" --help 2> /dev/null | \
    grep -q "^Reference: T. Rognes (2011)" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="--help message lists 26 options"
"${SWIPE}" --help 2> /dev/null | \
    grep -Ec "^  -[a-zA-Z], --" | \
    grep -qx "26" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## help is printed and swipe stops, even if other options are invalid
DESCRIPTION="--help stops swipe before other options are checked"
"${SWIPE}" --num_threads 0 --help 2> /dev/null | \
    grep -q "^Usage: " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## options after --help are not parsed
DESCRIPTION="--help stops swipe before the next options are parsed"
"${SWIPE}" --help --unknown_option 2>&1 | \
    grep -q "unrecognized" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"

## there is no --version option
DESCRIPTION="--version is not a valid option"
"${SWIPE}" --version > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"


#*****************************************************************************#
#                                                                             #
#                         option parsing (getopt_long)                        #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="swipe without any option fails"
"${SWIPE}" < /dev/null > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"

DESCRIPTION="swipe without any option: error message (no database)"
"${SWIPE}" < /dev/null 2>&1 | \
    grep -qx "No database specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="unknown long option fails"
"${SWIPE}" --unknown_option < /dev/null > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"

DESCRIPTION="unknown short option fails"
"${SWIPE}" -Z < /dev/null > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"

DESCRIPTION="unknown option: usage message is written to stdout"
"${SWIPE}" -Z < /dev/null 2> /dev/null | \
    grep -q "^Usage: " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="unknown option: error message is written to stderr"
"${SWIPE}" -Z < /dev/null 2>&1 > /dev/null | \
    grep -q "invalid option -- 'Z'" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="unknown option: usage message has no program header"
"${SWIPE}" -Z < /dev/null 2> /dev/null | \
    grep -q "^SWIPE " && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"

DESCRIPTION="missing option argument fails"
"${SWIPE}" -d < /dev/null > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"

DESCRIPTION="missing option argument: error message"
"${SWIPE}" -d < /dev/null 2>&1 > /dev/null | \
    grep -q "option requires an argument -- 'd'" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="long options accept the --option=value syntax"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db="${DB}" \
        --outfmt=8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="short options accept the -ovalue syntax"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        -d"${DB}" \
        -m8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## getopt_long accepts unambiguous abbreviations of long options
DESCRIPTION="long options can be abbreviated (--outf for --outfmt)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outf 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ambiguous abbreviations of long options are rejected (--num)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num 2 2>&1 > /dev/null | \
    grep -q "option '--num' is ambiguous" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## --d could be --db, --db_gencode, --dump or --dbsize
DESCRIPTION="ambiguous abbreviations of long options are rejected (--d)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --d "${DB}" > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## non-option arguments are silently ignored (getopt permutes them)
DESCRIPTION="extra non-option arguments are silently ignored"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 \
        extra_argument | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="when an option is repeated, the last value is used"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 3 \
        --num_descriptions 7 | \
    grep -qx "Max matches shown: 7" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## numerical values are parsed with atol() and atof(): no error is
## reported for non-numerical values or trailing characters
DESCRIPTION="numerical values: trailing characters are silently ignored"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 7abc | \
    grep -qx "Max matches shown: 7" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="numerical values: non-numerical values are read as zero"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions abc | \
    grep -qx "Max matches shown: 0" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                         mandatory options: --db (-d)                        #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="--db is mandatory"
printf ">q1\nMKV\n" | \
    "${SWIPE}" > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"

DESCRIPTION="--db is mandatory (error message)"
printf ">q1\nMKV\n" | \
    "${SWIPE}" 2>&1 | \
    grep -qx "No database specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="--db rejects an empty database name"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "" 2>&1 | \
    grep -qx "No database specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="-d is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        -d "${DB}" > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--db is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--db is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database file:     ${DB}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--db a missing database fails"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db missing_database > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"

DESCRIPTION="--db a missing database (error message)"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db missing_database 2>&1 | \
    grep -qx "Unable to open file missing_database.pin." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"


#*****************************************************************************#
#                                                                             #
#                          default parameter values                           #
#                                                                             #
#*****************************************************************************#

## check the parameter block printed when using default values
for LINE in \
    "Query file name:   -" \
        "Query length:      3 residues" \
        "Query description: q1" \
        "Score matrix:      BLOSUM62" \
        "Gap penalty:       11+1k" \
        "Max expect shown:  10" \
        "Min score shown:   1" \
        "Max matches shown: 250" \
        "Alignments shown:  100" \
        "Show gi's:         0" \
        "Show taxid's:      0" \
        "Threads:           1" \
        "Symbol type:       Amino acid" ; do
    DESCRIPTION="default parameter block contains \"${LINE}\""
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" | \
        sed 's/ *$//' | \
        grep -qxF "${LINE}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset LINE

DESCRIPTION="default parameter block does not show the effective db size"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "db size" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="default parameter block does not show a taxid filename"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "^Taxid filename:" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the minimum expect value and the maximum score are never reported
DESCRIPTION="parameter block does not show the minimum expect value"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --minevalue 0.5 | \
    grep -qi "min expect" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="parameter block does not show the maximum score"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --max_score 99 | \
    grep -qi "max score" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                            --query (-i) option                              #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="--query reads from stdin by default"
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

DESCRIPTION="--query - reads from stdin"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --query - \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="-i - reads from stdin"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -i - \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--query reads from a file"
DB=$(printf ">s1\nMKV\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --query <(printf ">q1\nMKV\n") \
    --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--query reads from /dev/stdin"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --query /dev/stdin \
        --outfmt 8 | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--query is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
QUERY=$(mktemp)
printf ">q1\nMKV\n" > "${QUERY}"
"${SWIPE}" \
    --db "${DB}" \
    --query "${QUERY}" | \
    grep -qx "Query file name:   ${QUERY}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${QUERY}"
remove_db "${DB}"
unset DB QUERY

DESCRIPTION="--query a missing file fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --query missing_file.fasta > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--query a missing file (error message)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --query missing_file.fasta 2>&1 | \
    grep -qx "Cannot open query file." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the database is opened before the query file
DESCRIPTION="--query a missing file and a missing database (db error first)"
"${SWIPE}" \
    --db missing_database \
    --query missing_file.fasta 2>&1 | \
    grep -q "^Unable to open file missing_database" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="--query an unreadable file fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
QUERY=$(mktemp)
printf ">q1\nMKV\n" > "${QUERY}"
chmod u-r "${QUERY}"
"${SWIPE}" \
    --db "${DB}" \
    --query "${QUERY}" > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
chmod u+r "${QUERY}"
rm -f "${QUERY}"
remove_db "${DB}"
unset DB QUERY


#*****************************************************************************#
#                                                                             #
#                             --out (-o) option                               #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="--out writes results to a file"
DB=$(printf ">s1\nMKV\n" | make_db prot)
OUTPUT=$(mktemp)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 \
        --out "${OUTPUT}"
grep -q "^q1" "${OUTPUT}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${OUTPUT}"
remove_db "${DB}"
unset DB OUTPUT

DESCRIPTION="-o writes results to a file"
DB=$(printf ">s1\nMKV\n" | make_db prot)
OUTPUT=$(mktemp)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 \
        -o "${OUTPUT}"
grep -q "^q1" "${OUTPUT}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${OUTPUT}"
remove_db "${DB}"
unset DB OUTPUT

DESCRIPTION="--out writes nothing to stdout"
DB=$(printf ">s1\nMKV\n" | make_db prot)
OUTPUT=$(mktemp)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --out "${OUTPUT}" | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
rm -f "${OUTPUT}"
remove_db "${DB}"
unset DB OUTPUT

DESCRIPTION="--out /dev/stdout writes to stdout"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 \
        --out /dev/stdout | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--out overwrites an existing file"
DB=$(printf ">s1\nMKV\n" | make_db prot)
OUTPUT=$(mktemp)
printf "previous content\n" > "${OUTPUT}"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 \
        --out "${OUTPUT}"
grep -q "previous content" "${OUTPUT}" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
rm -f "${OUTPUT}"
remove_db "${DB}"
unset DB OUTPUT

DESCRIPTION="--out a file in a missing directory fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --out missing_directory/output.txt > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--out a file in a missing directory (error message)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --out missing_directory/output.txt 2>&1 | \
    grep -qx "Unable to open output file for writing." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--out a non-writable file fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
OUTPUT=$(mktemp)
chmod u-w "${OUTPUT}"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --out "${OUTPUT}" > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
chmod u+w "${OUTPUT}"
rm -f "${OUTPUT}"
remove_db "${DB}"
unset DB OUTPUT

## the output file is opened before the other options are checked
DESCRIPTION="--out is created even when other options are invalid"
OUTPUT=$(mktemp -u)
"${SWIPE}" \
    --num_threads 0 \
    --out "${OUTPUT}" < /dev/null > /dev/null 2>&1
[[ -e "${OUTPUT}" ]] && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${OUTPUT}"
unset OUTPUT

DESCRIPTION="--out is truncated even when other options are invalid"
OUTPUT=$(mktemp)
printf "previous content\n" > "${OUTPUT}"
"${SWIPE}" \
    --num_threads 0 \
    --out "${OUTPUT}" < /dev/null > /dev/null 2>&1
[[ -s "${OUTPUT}" ]] && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
rm -f "${OUTPUT}"
unset OUTPUT

## error messages are not written to the output file
DESCRIPTION="--out error messages are written to stderr"
OUTPUT=$(mktemp)
"${SWIPE}" \
    --num_threads 0 \
    --out "${OUTPUT}" < /dev/null 2>&1 | \
    grep -qx "Illegal number of threads specified" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${OUTPUT}"
unset OUTPUT

## the help message is printed before --out is processed
DESCRIPTION="--out is ignored by --help (help written to stdout)"
OUTPUT=$(mktemp)
"${SWIPE}" \
    --out "${OUTPUT}" \
    --help 2> /dev/null | \
    grep -q "^Usage: " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${OUTPUT}"
unset OUTPUT


#*****************************************************************************#
#                                                                             #
#                          --num_threads (-a) option                          #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="-a is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -a 2 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--num_threads is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_threads 2 | \
    grep -qx "Threads:           2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

for THREADS in 1 2 8 256 ; do
    DESCRIPTION="--num_threads ${THREADS} is accepted"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --num_threads "${THREADS}" > /dev/null && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset THREADS

for THREADS in 0 257 -1 abc "" ; do
    DESCRIPTION="--num_threads \"${THREADS}\" is rejected"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --num_threads "${THREADS}" 2>&1 | \
        grep -qx "Illegal number of threads specified" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset THREADS

## more threads than database sequences
DESCRIPTION="--num_threads 256 with a single database sequence"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_threads 256 \
        --outfmt 8 | \
    grep -c "^q1" | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                            --outfmt (-m) option                             #
#                                                                             #
#*****************************************************************************#

## see output.sh for the content of each output format

for OUTFMT in 0 7 8 9 99 ; do
    DESCRIPTION="--outfmt ${OUTFMT} is accepted"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --outfmt "${OUTFMT}" > /dev/null && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset OUTFMT

DESCRIPTION="-m is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -m 8 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

for OUTFMT in -1 1 2 3 4 5 6 10 98 100 ; do
    DESCRIPTION="--outfmt ${OUTFMT} is rejected"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --outfmt "${OUTFMT}" 2>&1 | \
        grep -qx "Illegal view type." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset OUTFMT

## atol("abc") = 0
DESCRIPTION="--outfmt abc is read as --outfmt 0"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt abc | \
    grep -q "^Sequences producing significant alignments:" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                            --symtype (-p) option                            #
#                                                                             #
#*****************************************************************************#

## Numeric String  Query  Database Comparisons
## 0       blastn  NT     NT       Direct + reverse complementary
## 1       blastp  AA     AA       Direct
## 2       blastx  NT     AA       Translated query (6 frames)
## 3       tblastn AA     NT       Translated database (6 frames)
## 4       tblastx NT     NT       Translated query and database (6x6 frames)
## (5      sound, undocumented, see sound.sh)

DESCRIPTION="-p is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -p 1 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## symtype, name, database type, symbol type reported in the parameter block
while read -r NUMBER NAME DBTYPE REPORTED ; do
    DESCRIPTION="--symtype ${NUMBER} is reported as ${REPORTED}"
    DB=$(printf ">s1\nACGTACGTACGT\n" | make_db "${DBTYPE}")
    printf ">q1\nACGTACGTACGT\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype "${NUMBER}" | \
        grep -qx "Symbol type:       ${REPORTED}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"

    DESCRIPTION="--symtype ${NAME} is reported as ${REPORTED}"
    printf ">q1\nACGTACGTACGT\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype "${NAME}" | \
        grep -qx "Symbol type:       ${REPORTED}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
0 blastn nucl Nucleotide
1 blastp prot Amino acid
2 blastx prot Translated query
3 tblastn nucl Translated database
4 tblastx nucl Both translated
5 sound prot Sound
EOF
unset NUMBER NAME DBTYPE REPORTED

## names are case-sensitive, and unknown names are parsed with
## atol(), so they silently select symtype 0 (blastn, see
## known_issues.sh)
DESCRIPTION="--symtype names are case-sensitive (BLASTP is read as 0)"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype BLASTP | \
    grep -qx "Symbol type:       Nucleotide" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

for SYMTYPE in -1 6 7 ; do
    DESCRIPTION="--symtype ${SYMTYPE} is rejected"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype "${SYMTYPE}" \
            --gapopen 11 \
            --gapextend 1 2>&1 | \
        grep -qx "Illegal symbol type." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset SYMTYPE

## no default gap penalties are set for symbol types above 5, but the
## symbol type is checked first (KI-5, see fixed_bugs.sh)
DESCRIPTION="--symtype 6 without gap penalties: symbol type error"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 6 2>&1 | \
    grep -qx "Illegal symbol type." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the database type is chosen by the symbol type: protein database
## (.pin, .phr, .psq) for 1, 2 and 5, nucleotide database (.nin,
## .nhr, .nsq) for 0, 3 and 4
while read -r SYMTYPE EXTENSION ; do
    DESCRIPTION="--symtype ${SYMTYPE} opens a database file with extension ${EXTENSION}"
    printf ">q1\nACGT\n" | \
        "${SWIPE}" \
            --db missing_database \
            --symtype "${SYMTYPE}" 2>&1 | \
        grep -qx "Unable to open file missing_database.${EXTENSION}." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
done <<EOF
0 nin
1 pin
2 pin
3 nin
4 nin
5 pin
EOF
unset SYMTYPE EXTENSION


#*****************************************************************************#
#                                                                             #
#                            --strand (-S) option                             #
#                                                                             #
#*****************************************************************************#

## see blastn.sh and blastx.sh for the effect on search results

DESCRIPTION="-S is accepted"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        -S 1 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

while read -r STRAND REPORTED ; do
    DESCRIPTION="--strand ${STRAND} is reported as ${REPORTED}"
    DB=$(printf ">s1\nACGT\n" | make_db nucl)
    printf ">q1\nACGT\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype 0 \
            --strand "${STRAND}" | \
        grep -qx "Query strands:     ${REPORTED}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
1 Plus
2 Minus
3 Plus and minus
plus Plus
minus Minus
both Plus and minus
EOF
unset STRAND REPORTED

DESCRIPTION="--strand default is both strands"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 | \
    grep -qx "Query strands:     Plus and minus" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## query strands are only reported for blastn
DESCRIPTION="--strand is not reported in the parameter block of blastp"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --strand 1 | \
    grep -q "^Query strands:" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

for STRAND in 0 4 -1 forward PLUS abc ; do
    DESCRIPTION="--strand ${STRAND} is rejected"
    DB=$(printf ">s1\nACGT\n" | make_db nucl)
    printf ">q1\nACGT\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype 0 \
            --strand "${STRAND}" 2>&1 | \
        grep -qx "Illegal query strands specified." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset STRAND

## the minus strand makes no sense for protein queries (tblastx
## queries are nucleotides: --strand 2 is accepted, KI-4, see
## fixed_bugs.sh)
for SYMTYPE in 1 3 ; do
    DESCRIPTION="--strand 2 is rejected with --symtype ${SYMTYPE}"
    printf ">q1\nACGT\n" | \
        "${SWIPE}" \
            --db missing_database \
            --symtype "${SYMTYPE}" \
            --strand 2 2>&1 | \
        grep -qx "Illegal strand specified for protein query." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
done
unset SYMTYPE

## plus-strand (1) and both strands (3) are silently accepted with
## protein queries
for SYMTYPE in 1 3 ; do
    DESCRIPTION="--strand 1 is accepted with --symtype ${SYMTYPE}"
    printf ">q1\nACGT\n" | \
        "${SWIPE}" \
            --db missing_database \
            --symtype "${SYMTYPE}" \
            --strand 1 2>&1 | \
        grep -q "^Unable to open file" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
done
unset SYMTYPE

## the sound symtype (5) accepts all strand values
DESCRIPTION="--strand 2 is accepted with --symtype 5"
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db missing_database \
        --symtype 5 \
        --strand 2 2>&1 | \
    grep -q "^Unable to open file" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"


#*****************************************************************************#
#                                                                             #
#               --query_gencode (-Q) and --db_gencode (-D) options            #
#                                                                             #
#*****************************************************************************#

## see blastx.sh, tblastn.sh and tblastx.sh for the effect on search
## results

## valid NCBI genetic codes in swipe: 1-6, 9-16, 21-23
for CODE in 1 2 3 4 5 6 9 10 11 12 13 14 15 16 21 22 23 ; do
    DESCRIPTION="--query_gencode ${CODE} is accepted"
    printf ">q1\nACGT\n" | \
        "${SWIPE}" \
            --db missing_database \
            --query_gencode "${CODE}" 2>&1 | \
        grep -q "^Unable to open file" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"

    DESCRIPTION="--db_gencode ${CODE} is accepted"
    printf ">q1\nACGT\n" | \
        "${SWIPE}" \
            --db missing_database \
            --db_gencode "${CODE}" 2>&1 | \
        grep -q "^Unable to open file" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
done
unset CODE

## help message says [1-23], but codes 7, 8 and 17 to 20 do not exist
for CODE in -1 0 7 8 17 18 19 20 24 25 abc ; do
    DESCRIPTION="--query_gencode ${CODE} is rejected"
    printf ">q1\nACGT\n" | \
        "${SWIPE}" \
            --db missing_database \
            --query_gencode "${CODE}" 2>&1 | \
        grep -qx "Illegal query genetic code specified." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"

    DESCRIPTION="--db_gencode ${CODE} is rejected"
    printf ">q1\nACGT\n" | \
        "${SWIPE}" \
            --db missing_database \
            --db_gencode "${CODE}" 2>&1 | \
        grep -qx "Illegal database genetic code specified." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
done
unset CODE

DESCRIPTION="-Q is accepted"
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db missing_database \
        -Q 2 2>&1 | \
    grep -q "^Unable to open file" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="-D is accepted"
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db missing_database \
        -D 2 2>&1 | \
    grep -q "^Unable to open file" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## genetic codes are checked even if no translation is performed
DESCRIPTION="--query_gencode is checked for blastp searches"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db missing_database \
        --symtype 1 \
        --query_gencode 7 2>&1 | \
    grep -qx "Illegal query genetic code specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## query genetic code is only reported for blastx and tblastx
while read -r SYMTYPE DBTYPE COUNT ; do
    DESCRIPTION="--symtype ${SYMTYPE} reports ${COUNT} query genetic code"
    DB=$(printf ">s1\nACGTACGTACGT\n" | make_db "${DBTYPE}")
    printf ">q1\nACGTACGTACGT\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype "${SYMTYPE}" \
            --query_gencode 2 | \
        grep -c "^Query genetic code:Vertebrate Mitochondrial Code (2)$" | \
        grep -qx "${COUNT}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
0 nucl 0
1 prot 0
2 prot 1
3 nucl 0
4 nucl 1
EOF
unset SYMTYPE DBTYPE COUNT

## database genetic code is only reported for tblastn and tblastx
while read -r SYMTYPE DBTYPE COUNT ; do
    DESCRIPTION="--symtype ${SYMTYPE} reports ${COUNT} database genetic code"
    DB=$(printf ">s1\nACGTACGTACGT\n" | make_db "${DBTYPE}")
    printf ">q1\nACGTACGTACGT\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype "${SYMTYPE}" \
            --db_gencode 11 | \
        grep -c "^DB genetic code:   Bacterial, Archaeal and Plant Plastid Code (11)$" | \
        grep -qx "${COUNT}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
0 nucl 0
1 prot 0
2 prot 0
3 nucl 1
4 nucl 1
EOF
unset SYMTYPE DBTYPE COUNT

## names of all valid genetic codes
while read -r CODE NAME ; do
    DESCRIPTION="--query_gencode ${CODE} is named ${NAME}"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nACGTACGTACGT\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --symtype 2 \
            --query_gencode "${CODE}" | \
        grep -qxF "Query genetic code:${NAME} (${CODE})" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
1 Standard Code
2 Vertebrate Mitochondrial Code
3 Yeast Mitochondrial Code
4 Mold, Protozoan, and Coelenterate Mitochondrial Code and Mycoplasma/Spiroplasma Code
5 Invertebrate Mitochondrial Code
6 Ciliate, Dasycladacean and Hexamita Nuclear Code
9 Echinoderm and Flatworm Mitochondrial Code
10 Euplotid Nuclear Code
11 Bacterial, Archaeal and Plant Plastid Code
12 Alternative Yeast Nuclear Code
13 Ascidian Mitochondrial Code
14 Alternative Flatworm Mitochondrial Code
15 Blepharisma Nuclear Code
16 Chlorophycean Mitochondrial Code
21 Trematode Mitochondrial Code
22 Scenedesmus obliquus Mitochondrial Code
23 Thraustochytrium Mitochondrial Code
EOF
unset CODE NAME


#*****************************************************************************#
#                                                                             #
#                              --dump (-N) option                             #
#                                                                             #
#*****************************************************************************#

## see database.sh for the dump output

for DUMP in 0 1 2 ; do
    DESCRIPTION="--dump ${DUMP} is accepted"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    "${SWIPE}" \
        --db "${DB}" \
        --dump "${DUMP}" < /dev/null > /dev/null && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset DUMP

DESCRIPTION="-N is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    -N 1 < /dev/null > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

for DUMP in -1 3 ; do
    DESCRIPTION="--dump ${DUMP} is rejected"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    "${SWIPE}" \
        --db "${DB}" \
        --dump "${DUMP}" < /dev/null 2>&1 | \
        grep -qx "Illegal dump mode." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset DUMP


#*****************************************************************************#
#                                                                             #
#                             --dbsize (-z) option                            #
#                                                                             #
#*****************************************************************************#

## see blastp.sh for the effect on expect values

DESCRIPTION="-z is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -z 1000 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the typo "Effecive" is fixed (KI-34, see fixed_bugs.sh)
DESCRIPTION="--dbsize is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dbsize 1000 | \
    grep -qx "Effective db size: 1000" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--dbsize 0 (default) is not reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dbsize 0 | \
    grep -q "db size:" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--dbsize rejects negative values"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dbsize -1 2>&1 | \
    grep -qx "Illegal effective db size specified" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                  --show_gis (-I) and --show_taxid (-H) options              #
#                                                                             #
#*****************************************************************************#

## see output.sh for the effect on search results

DESCRIPTION="--show_gis is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_gis | \
    grep -qx "Show gi's:         1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="-I is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -I | \
    grep -qx "Show gi's:         1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_taxid is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_taxid | \
    grep -qx "Show taxid's:      1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="-H is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -H | \
    grep -qx "Show taxid's:      1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_gis does not take an argument"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_gis=1 > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                     --taxid (-x) option (taxid list file)                   #
#                                                                             #
#*****************************************************************************#

## see database.sh for the effect on search results

## the help message advertises --taxidlist, but the long option is
## named --taxid (see known_issues.sh)
DESCRIPTION="-x is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -x <(printf "0\n") > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--taxid is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "0\n") > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--taxid is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
TAXIDS=$(mktemp)
printf "0\n" > "${TAXIDS}"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid "${TAXIDS}" | \
    grep -qx "Taxid filename:    ${TAXIDS}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${TAXIDS}"
remove_db "${DB}"
unset DB TAXIDS

DESCRIPTION="--taxid a missing file fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid missing_file.txt > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--taxid a missing file (error message)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid missing_file.txt 2>&1 | \
    grep -qx "Unable to open taxid file missing_file.txt." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                      scoring options (-M, -G, -E, -q, -r)                   #
#                                                                             #
#*****************************************************************************#

## see blastp.sh and blastn.sh for the effect on search results

DESCRIPTION="--matrix is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix PAM70 | \
    grep -qx "Score matrix:      PAM70" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="-M is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -M PAM70 | \
    grep -qx "Score matrix:      PAM70" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## default gap penalties depend on the score matrix
while read -r MATRIX PENALTIES ; do
    DESCRIPTION="--matrix ${MATRIX} default gap penalties are ${PENALTIES}"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --matrix "${MATRIX}" | \
        grep -qx "Gap penalty:       ${PENALTIES}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
BLOSUM45 14+2k
BLOSUM50 13+2k
BLOSUM62 11+1k
BLOSUM80 11+1k
BLOSUM90 10+1k
PAM30 9+1k
PAM70 10+1k
PAM250 15+2k
EOF
unset MATRIX PENALTIES

DESCRIPTION="--matrix names are case-insensitive"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix pam70 | \
    grep -qx "Gap penalty:       10+1k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--matrix unknown name without gap penalties is rejected"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix unknown_matrix 2>&1 | \
    grep -qx "Unknown score matrix. Gap penalties must be specified (-G and -E)." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## an unknown matrix name is a file name
DESCRIPTION="--matrix unknown name with gap penalties (missing file)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix unknown_matrix \
        --gapopen 10 \
        --gapextend 1 2>&1 | \
    grep -qx "Cannot open score matrix file." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## one gap penalty is enough to accept an unknown matrix
DESCRIPTION="--matrix unknown name with --gapopen only (missing file)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix unknown_matrix \
        --gapopen 10 2>&1 | \
    grep -qx "Cannot open score matrix file." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--matrix unknown name with --gapextend only (missing file)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --matrix unknown_matrix \
        --gapextend 1 2>&1 | \
    grep -qx "Cannot open score matrix file." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--gapopen is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 9 | \
    grep -qx "Gap penalty:       9+1k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--gapextend is reported in the parameter block"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapextend 2 | \
    grep -qx "Gap penalty:       11+2k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="-G and -E are accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -G 9 \
        -E 2 | \
    grep -qx "Gap penalty:       9+2k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## zero means "use the default value" (see known_issues.sh)
DESCRIPTION="--gapopen 0 is replaced by the default value"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 0 | \
    grep -qx "Gap penalty:       11+1k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--gapextend 0 is replaced by the default value"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapextend 0 | \
    grep -qx "Gap penalty:       11+1k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--gapopen rejects negative values"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen -1 2>&1 | \
    grep -qx "Illegal gap penalties." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--gapextend rejects negative values"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapextend -1 2>&1 | \
    grep -qx "Illegal gap penalties." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--penalty and --reward are reported in the parameter block"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --penalty -2 \
        --reward 3 | \
    grep -qx "Score matrix:      3/-2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="-q and -r are accepted"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        -q -2 \
        -r 3 | \
    grep -qx "Score matrix:      3/-2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--symtype 0 default nucleotide scores are 1/-3"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 | \
    grep -qx "Score matrix:      1/-3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--symtype 0 default gap penalties are 5+2k"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 | \
    grep -qx "Gap penalty:       5+2k" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## scores are not validated: a positive mismatch penalty is accepted
DESCRIPTION="--penalty accepts positive values"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --penalty 2 | \
    grep -qx "Score matrix:      1/2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the matrix option is ignored by nucleotide searches
DESCRIPTION="--matrix is ignored with --symtype 0"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --matrix PAM70 | \
    grep -qx "Score matrix:      1/-3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## scoring options for nucleotides are ignored by protein searches
DESCRIPTION="--reward is ignored with --symtype 1"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 1 \
        --reward 5 | \
    grep -qx "Score matrix:      BLOSUM62" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                   reporting options (-v, -b, -e, -k, -c, -u)                #
#                                                                             #
#*****************************************************************************#

## see blastp.sh for the effect on search results

while read -r OPTION VALUE LINE ; do
    DESCRIPTION="${OPTION} ${VALUE} is reported as \"${LINE}\""
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            "${OPTION}" "${VALUE}" | \
        grep -qxF "${LINE}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
--num_descriptions 5 Max matches shown: 5
-v 5 Max matches shown: 5
--num_alignments 5 Alignments shown:  5
-b 5 Alignments shown:  5
--evalue 0.5 Max expect shown:  0.5
-e 0.5 Max expect shown:  0.5
--evalue 1e-10 Max expect shown:  1e-10
--min_score 5 Min score shown:   5
-c 5 Min score shown:   5
EOF
unset OPTION VALUE LINE

for OPTION in -k --minevalue -u --max_score ; do
    DESCRIPTION="${OPTION} is accepted"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            "${OPTION}" 5 > /dev/null && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset OPTION

## values are not validated
for OPTION in --num_descriptions --num_alignments --evalue --minevalue \
                                 --min_score --max_score ; do
    DESCRIPTION="${OPTION} accepts negative values"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            "${OPTION}" -1 > /dev/null 2>&1 && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset OPTION


#*****************************************************************************#
#                                                                             #
#                   undocumented options (-C, -F, -K)                         #
#                                                                             #
#*****************************************************************************#

## BLAST options accepted for compatibility: composition-based
## statistics (-C) and query filtering (-F) are only accepted when
## disabled, the number of subalignments (-K) is accepted and ignored

for VALUE in F f 0 ; do
    DESCRIPTION="--comp_based_stats ${VALUE} is accepted"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --comp_based_stats "${VALUE}" > /dev/null && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset VALUE

for VALUE in T t 1 2 "" ; do
    DESCRIPTION="--comp_based_stats \"${VALUE}\" is rejected"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --comp_based_stats "${VALUE}" 2>&1 | \
        grep -qx "Composition-based score adjustments not supported." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset VALUE

DESCRIPTION="-C F is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -C F > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

for VALUE in F f "" ; do
    DESCRIPTION="--filter \"${VALUE}\" is accepted"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --filter "${VALUE}" > /dev/null && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset VALUE

## BLAST accepts -F 0 to disable filtering, swipe does not
for VALUE in T t 0 1 ; do
    DESCRIPTION="--filter ${VALUE} is rejected"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --filter "${VALUE}" 2>&1 | \
        grep -qx "Query sequence filtering not supported." && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset VALUE

DESCRIPTION="-F F is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -F F > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

for VALUE in 0 1 5 -1 abc ; do
    DESCRIPTION="--subalignments ${VALUE} is accepted"
    DB=$(printf ">s1\nMKV\n" | make_db prot)
    printf ">q1\nMKV\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --subalignments "${VALUE}" > /dev/null && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done
unset VALUE

DESCRIPTION="--subalignments has no effect on results"
DB=$(printf ">s1\nMKV\n>s2\nMKVW\n" | make_db prot)
diff \
    <(printf ">q1\nMKV\n" | \
          "${SWIPE}" \
              --db "${DB}" \
              --outfmt 8) \
    <(printf ">q1\nMKV\n" | \
          "${SWIPE}" \
              --db "${DB}" \
              --outfmt 8 \
              --subalignments 5) > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="-K is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        -K 1 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                           order of the checks                               #
#                                                                             #
#*****************************************************************************#

## options are checked in this order: effective db size, threads,
## database, output format, gap penalties, symbol type, strands,
## genetic codes, dump mode

DESCRIPTION="checks: effective db size is checked before threads"
"${SWIPE}" \
    --dbsize -1 \
    --num_threads 0 < /dev/null 2>&1 | \
    grep -qx "Illegal effective db size specified" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="checks: threads are checked before database"
"${SWIPE}" \
    --num_threads 0 < /dev/null 2>&1 | \
    grep -qx "Illegal number of threads specified" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="checks: database is checked before output format"
"${SWIPE}" \
    --outfmt 1 < /dev/null 2>&1 | \
    grep -qx "No database specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="checks: output format is checked before gap penalties"
"${SWIPE}" \
    --db missing_database \
    --outfmt 1 \
    --gapopen -1 < /dev/null 2>&1 | \
    grep -qx "Illegal view type." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="checks: output format is checked before symbol type"
"${SWIPE}" \
    --db missing_database \
    --outfmt 1 \
    --symtype 6 < /dev/null 2>&1 | \
    grep -qx "Illegal view type." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="checks: symbol type is checked before gap penalties"
"${SWIPE}" \
    --db missing_database \
    --gapopen -1 \
    --symtype 6 < /dev/null 2>&1 | \
    grep -qx "Illegal symbol type." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="checks: gap penalties are checked before strands"
"${SWIPE}" \
    --db missing_database \
    --gapopen -1 \
    --strand 0 < /dev/null 2>&1 | \
    grep -qx "Illegal gap penalties." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="checks: strands are checked before genetic codes"
"${SWIPE}" \
    --db missing_database \
    --strand 0 \
    --query_gencode 0 < /dev/null 2>&1 | \
    grep -qx "Illegal query strands specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="checks: query genetic code is checked before db genetic code"
"${SWIPE}" \
    --db missing_database \
    --query_gencode 0 \
    --db_gencode 0 < /dev/null 2>&1 | \
    grep -qx "Illegal query genetic code specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

DESCRIPTION="checks: genetic codes are checked before dump mode"
"${SWIPE}" \
    --db missing_database \
    --db_gencode 0 \
    --dump 3 < /dev/null 2>&1 | \
    grep -qx "Illegal database genetic code specified." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## the matrix is checked (and default gap penalties are set) before
## all other checks
DESCRIPTION="checks: unknown matrix is checked before threads"
"${SWIPE}" \
    --matrix unknown_matrix \
    --num_threads 0 < /dev/null 2>&1 | \
    grep -q "^Unknown score matrix." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"

## the database is opened after all option checks
DESCRIPTION="checks: dump mode is checked before opening the database"
"${SWIPE}" \
    --db missing_database \
    --dump 3 < /dev/null 2>&1 | \
    grep -qx "Illegal dump mode." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"


exit 0
