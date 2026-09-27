#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="databases"
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


## A database version 4 made of three files: an index (.pin or .nin),
## headers (.phr or .nhr, binary ASN.1), and sequences (.psq or
## .nsq). Alias files (.pal or .nal) group several volumes or select
## a subset of sequences (OID mask files). Description of the format:
## http://selab.janelia.org/people/farrarm/blastdbfmtv4/blastdbfmt.html


#*****************************************************************************#
#                                                                             #
#                            opening a database                               #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="database: a protein database is accepted"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: a nucleotide database is accepted"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: a nucleotide database with --symtype 1 fails"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 1 2>&1 | \
    grep -qx "Unable to open file ${DB}.pin." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: a protein database with --symtype 0 fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 2>&1 | \
    grep -qx "Unable to open file ${DB}.nin." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: missing index file (.pin) fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
rm -f "${DB}.pin"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: missing header file (.phr) fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
rm -f "${DB}.phr"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: missing header file (.phr) (error message)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
rm -f "${DB}.phr"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    grep -qx "Unable to open file ${DB}.phr." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: missing sequence file (.psq) fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
rm -f "${DB}.psq"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: missing sequence file (.psq) (error message)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
rm -f "${DB}.psq"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    grep -qx "Unable to open file ${DB}.psq." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the error message for the sequence file ends with a single
## newline (KI-35, see fixed_bugs.sh)
DESCRIPTION="database: missing sequence file (.psq) (no extra empty line)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
rm -f "${DB}.psq"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: missing nucleotide sequence file (.nsq) fails"
DB=$(printf ">s1\nACGT\n" | make_db nucl)
rm -f "${DB}.nsq"
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 2>&1 | \
    grep -qx "Unable to open file ${DB}.nsq." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: empty index file fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
: > "${DB}.pin"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    grep -qx "Unable to map file ${DB}.pin in memory. It may be empty or too large." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: unreadable index file fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
chmod u-r "${DB}.pin"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" > /dev/null 2>&1 && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
chmod u+r "${DB}.pin"
remove_db "${DB}"
unset DB

## current makeblastdb creates databases version 5 by default
DESCRIPTION="database: version 5 is rejected"
DB_DIR=$(mktemp -d)
printf ">s1\nMKV\n" | \
    makeblastdb \
        -dbtype prot \
        -blastdb_version 5 \
        -in - \
        -title "test" \
        -out "${DB_DIR}/db" > /dev/null 2>&1
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB_DIR}/db" 2>&1 | \
    grep -qx "Illegal database version (must be 4)." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${DB_DIR}"
unset DB_DIR

DESCRIPTION="database: version number is checked (version 3 is rejected)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf '\x00\x00\x00\x03' | \
    dd of="${DB}.pin" bs=1 seek=0 count=4 conv=notrunc 2> /dev/null
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    grep -qx "Illegal database version (must be 4)." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: base name with a relative path"
DB=$(printf ">s1\nMKV\n" | make_db prot)
(cd "$(dirname "$(dirname "${DB}")")" && \
     printf ">q1\nMKV\n" | \
         "${SWIPE}" \
             --db "$(basename "$(dirname "${DB}")")/db" \
             --outfmt 8) | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: base name without path (current directory)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
(cd "$(dirname "${DB}")" && \
     printf ">q1\nMKV\n" | \
         "${SWIPE}" \
             --db db \
             --outfmt 8) | \
    grep -q "^q1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## a file extension is not stripped from the base name
DESCRIPTION="database: base name with a file extension fails"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}.pin" 2>&1 | \
    grep -qx "Unable to open file ${DB}.pin.pin." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                      database information (parameter block)                 #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="database: title is reported"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database title:    test" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: title with spaces is reported"
DB_DIR=$(mktemp -d)
printf ">s1\nMKV\n" | \
    makeblastdb \
        -dbtype prot \
        -blastdb_version 4 \
        -in - \
        -title "a long title" \
        -out "${DB_DIR}/db" > /dev/null 2>&1
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB_DIR}/db" | \
    grep -qx "Database title:    a long title" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${DB_DIR}"
unset DB_DIR

DESCRIPTION="database: creation time is reported"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -Eqx "Database time:     [A-Z][a-z]{2} [0-9]{1,2}, [0-9]{4} +[0-9]{1,2}:[0-9]{2} [AP]M" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: number of residues and sequences are reported"
DB=$(printf ">s1\nMKV\n>s2\nMKVWW\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     8 residues in 2 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: length of the longest sequence is reported"
DB=$(printf ">s1\nMKV\n>s2\nMKVWW\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Longest db seq:    5 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: nucleotide database size is in nucleotides"
DB=$(printf ">s1\nACGTACGTAC\n>s2\nACG\n" | make_db nucl)
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 | \
    grep -qx "Database size:     13 residues in 2 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="database: database file name is reported as given"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database file:     ${DB}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                          sequence identifiers                               #
#                                                                             #
#*****************************************************************************#

## identifiers are decoded from the binary ASN.1 header file

DESCRIPTION="seqids: default identifiers are gnl|BL_ORD_ID|<number>"
DB=$(printf ">s1 description\nMKV\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    grep -qx ">gnl|BL_ORD_ID|0 s1 description" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="seqids: ordinal identifiers start at zero and are incremented"
DB=$(printf ">s1\nMKV\n>s2\nMKVW\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    grep "^>" | \
    tr "\n" " " | \
    grep -qx ">gnl|BL_ORD_ID|0 s1 >gnl|BL_ORD_ID|1 s2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## makeblastdb -parse_seqids: identifiers are parsed and stored
while read -r HEADER EXPECTED ; do
    DESCRIPTION="seqids: ${HEADER} is reported as ${EXPECTED}"
    DB=$(printf ">%s\nMKV\n" "${HEADER}" | make_db prot -parse_seqids)
    "${SWIPE}" \
        --db "${DB}" \
        --dump 1 < /dev/null | \
        grep -qxF ">${EXPECTED}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
s1 lcl|s1
lcl|s1 lcl|s1
AB000001.1 lcl|AB000001.1
gi|123 gi|123
gi|123|gb|AB000001.1| gi|123|gb|AB000001.1|
gb|AB000001.1| gb|AB000001.1|
emb|CAA00001.1| emb|CAA00001.1|
dbj|BAA00001.1| dbj|BAA00001.1|
ref|NP_000001.1| ref|NP_000001.1|
sp|P12345|NAME_HUMAN sp|P12345|NAME_HUMAN
tr|Q12345|NAME_MOUSE tr|Q12345|NAME_MOUSE
pir||A12345 pir||A12345
prf||123456A prf||123456A
tpg|DAA00001.1| tpg|DAA00001.1|
tpe|CAA00002.1| tpe|CAA00002.1|
tpd|FAA00001.1| tpd|FAA00001.1|
gpp|GPP00001.1| gpp|GPP00001.1|
nat|AAA00001.1| nat|AAA00001.1|
gnl|mydb|id42 gnl|mydb|id42
gnl|mydb|42 gnl|mydb|42
lcl|123 lcl|123
pat|US|1234567|1 pat|US|1234567|1
bbs|123 bbs|123
gim|123 gim|123
EOF
unset HEADER EXPECTED

DESCRIPTION="seqids: identifier and description are separated by a space"
DB=$(printf ">sp|P12345|NAME_HUMAN some protein\nMKV\n" | make_db prot -parse_seqids)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    grep -qx ">sp|P12345|NAME_HUMAN some protein" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## PDB identifiers: see fixed_bugs.sh (KI-22)

## corrupted header files: the header of ">gi|123 title" starts with
## 30 80 30 80 a0 80 1a 05 "title" 00 00 a1 80 30 80 ab 80 02 01 7b:
## the length of the title (05) is at offset 7, the length of the gi
## number (01) is at offset 22
DESCRIPTION="headers: illegal string length is rejected"
DB=$(printf ">gi|123 title\nMKV\n" | make_db prot -parse_seqids)
printf '\x85' | \
    dd of="${DB}.phr" bs=1 seek=7 count=1 conv=notrunc 2> /dev/null
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 2>&1 > /dev/null | \
    grep -qx "Error: illegal string length (85)." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="headers: illegal integer length is rejected"
DB=$(printf ">gi|123 title\nMKV\n" | make_db prot -parse_seqids)
printf '\x05' | \
    dd of="${DB}.phr" bs=1 seek=22 count=1 conv=notrunc 2> /dev/null
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 2>&1 > /dev/null | \
    grep -qx "Illegal length of integer object (05)." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="headers: corrupted header (error message)"
DB=$(printf ">gi|123 title\nMKV\n" | make_db prot -parse_seqids)
printf '\x05' | \
    dd of="${DB}.phr" bs=1 seek=22 count=1 conv=notrunc 2> /dev/null
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 2>&1 > /dev/null | \
    grep -qx "Error parsing binary ASN.1 in database sequence definition." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                       sequence titles (descriptions)                        #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="titles: a title of 2,048 characters is not truncated"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%02045d" 0)" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    head -n 1 | \
    awk '{exit length($0) == 2065 ? 0 : 1}' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## header strings are silently truncated to 2,048 characters
## (">gnl|BL_ORD_ID|0 " + 2,048 = 2,065)
DESCRIPTION="titles: titles longer than 2,048 characters are truncated"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%05000d" 0)" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    head -n 1 | \
    awk '{exit length($0) == 2065 ? 0 : 1}' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="titles: long titles do not prevent searches"
DB=$(printf ">s1 %s\nMKV\n" "$(printf "%05000d" 0)" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 2 | \
    grep -qx "gnl|BL_ORD_ID|0" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="titles: sequences without title have no trailing space"
DB=$(printf ">s1\nMKV\n" | make_db prot -parse_seqids)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    head -n 1 | \
    grep -qx ">lcl|s1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="titles: special characters are kept"
DB=$(printf ">s1 a<b>&c\"d'e\nMKV\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    head -n 1 | \
    grep -qx ">gnl|BL_ORD_ID|0 s1 a<b>&c\"d'e" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## in nr, identical sequences are merged into one entry with several
## deflines (separated by control-A characters in makeblastdb's input,
## see GitHub #4)
DESCRIPTION="titles: entry with 3 deflines, tabular output shows the first"
DB=$(printf ">sp|P1|A_HUMAN first\x01sp|P2|B_MOUSE second\x01sp|P3|C_RAT third\nMKVLAAGIVGLLLAW\n" | \
         make_db prot -parse_seqids)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^q1	sp|P1|A_HUMAN	100.00	15	" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="titles: entry with 3 deflines, plain output shows the last"
DB=$(printf ">sp|P1|A_HUMAN first\x01sp|P2|B_MOUSE second\x01sp|P3|C_RAT third\nMKVLAAGIVGLLLAW\n" | \
         make_db prot -parse_seqids)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx " sp|P3|C_RAT third *" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="titles: entry with 3 deflines, dump shows them on one line"
DB=$(printf ">sp|P1|A_HUMAN first\x01sp|P2|B_MOUSE second\x01sp|P3|C_RAT third\nMKVLAAGIVGLLLAW\n" | \
         make_db prot -parse_seqids)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    grep -qx ">sp|P1|A_HUMAN first >sp|P2|B_MOUSE second >sp|P3|C_RAT third" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                            dump (--dump, -N)                                #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="dump: --dump 1 prints the database in fasta format"
DB=$(printf ">s1\nMKV\n>s2\nMKVW\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    tr "\n" " " | \
    grep -qx ">gnl|BL_ORD_ID|0 s1 MKV >gnl|BL_ORD_ID|1 s2 MKVW " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: --dump 2 prints the database in fasta format"
DB=$(printf ">s1\nMKV\n>s2\nMKVW\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 2 < /dev/null | \
    tr "\n" " " | \
    grep -qx ">gnl|BL_ORD_ID|0 s1 MKV >gnl|BL_ORD_ID|1 s2 MKVW " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: --dump 0 does not dump the database"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --dump 0 | \
    grep -q "^Sequences producing" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: query is not read"
DB=$(printf ">s1\nMKV\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --query missing_file.fasta \
    --dump 1 > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: no program header"
DB=$(printf ">s1\nMKV\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    grep -q "^SWIPE" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: output format is ignored"
DB=$(printf ">s1\nMKV\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 \
    --outfmt 7 < /dev/null | \
    head -n 1 | \
    grep -qx ">gnl|BL_ORD_ID|0 s1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: output is written to --out"
DB=$(printf ">s1\nMKV\n" | make_db prot)
OUTPUT=$(mktemp)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 \
    --out "${OUTPUT}" < /dev/null
grep -qx "MKV" "${OUTPUT}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${OUTPUT}"
remove_db "${DB}"
unset DB OUTPUT

DESCRIPTION="dump: sequences are wrapped every 80 residues"
DB=$(printf ">s1\n%s\n" "$(printf "%0170d" 0 | tr "0" "M")" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    awk 'NR > 1 {print length($0)}' | \
    tr "\n" " " | \
    grep -qx "80 80 10 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: sequence of exactly 80 residues fits on one line"
DB=$(printf ">s1\n%s\n" "$(printf "%080d" 0 | tr "0" "M")" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: amino acids are uppercase"
DB=$(printf ">s1\nmkv\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "MKV" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: rare amino acids are preserved (BZXUO*)"
DB=$(printf ">s1\nMBZXUO*\n" | make_db prot)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qxF "MBZXUO*" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: nucleotide database (--symtype 0)"
DB=$(printf ">s1\nacgtacgtac\n" | make_db nucl)
"${SWIPE}" \
    --db "${DB}" \
    --symtype 0 \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "ACGTACGTAC" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## nucleotides are packed four per byte, test all remainders
for LENGTH in 1 2 3 4 5 ; do
    DESCRIPTION="dump: nucleotide sequence of length ${LENGTH}"
    SEQ=$(printf "ACGTA" | cut -c 1-"${LENGTH}")
    DB=$(printf ">s1\n%s\n" "${SEQ}" | make_db nucl)
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --dump 1 < /dev/null | \
        tail -n 1 | \
        grep -qx "${SEQ}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB SEQ
done
unset LENGTH

## ambiguous nucleotides are stored in a separate table
DESCRIPTION="dump: ambiguous nucleotides are preserved"
DB=$(printf ">s1\nACGTRYKMSWBDHVN\n" | make_db nucl)
"${SWIPE}" \
    --db "${DB}" \
    --symtype 0 \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "ACGTRYKMSWBDHVN" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## runs of ambiguous nucleotides are stored as runs of up to 16
DESCRIPTION="dump: long run of Ns is preserved (40 Ns)"
DB=$(printf ">s1\nACGT%sACGT\n" "$(printf "%040d" 0 | tr "0" "N")" | make_db nucl)
"${SWIPE}" \
    --db "${DB}" \
    --symtype 0 \
    --dump 1 < /dev/null | \
    tail -n 1 | \
    grep -qx "ACGT$(printf "%040d" 0 | tr "0" "N")ACGT" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: identifiers include gi numbers"
DB=$(printf ">gi|123|gb|AB000001.1| desc\nMKV\n" | make_db prot -parse_seqids)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    head -n 1 | \
    grep -qx ">gi|123|gb|AB000001.1| desc" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: --show_taxid adds taxids to identifiers"
DB=$(printf ">s1\nMKV\n" | make_db prot -parse_seqids -taxid 9606)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 \
    --show_taxid < /dev/null | \
    head -n 1 | \
    grep -qx ">lcl|s1|taxid|9606" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="dump: empty database (all sequences filtered out)"
DB=$(printf ">s1\nMKV\n" | make_db prot -parse_seqids -taxid 9606)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 \
    --taxid <(printf "10090\n") < /dev/null | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see fixed_bugs.sh (KI-24) for dumps of translated databases
## (--symtype 3 and 4)


#*****************************************************************************#
#                                                                             #
#                      alias files: several volumes                           #
#                                                                             #
#*****************************************************************************#

## an alias file lists database volumes (DBLIST), relative to the
## directory of the alias file

DESCRIPTION="alias: sequences of all volumes are searched"
DB1=$(printf ">a1\nMKVW\n" | make_db prot)
DB2=$(printf ">b1\nMKVW\n" | make_db prot)
ALIAS_DIR=$(mktemp -d)
cp "${DB1}".p* "${ALIAS_DIR}/"
rename_db () { for f in "${1}"/db.p* ; do mv "${f}" "${1}/${2}${f##*/db}" ; done ; }
rename_db "${ALIAS_DIR}" vol1
cp "${DB2}".p* "${ALIAS_DIR}/"
rename_db "${ALIAS_DIR}" vol2
printf "TITLE two volumes\nDBLIST vol1 vol2\n" > "${ALIAS_DIR}/alias.pal"
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${ALIAS_DIR}/alias" \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${ALIAS_DIR}"
remove_db "${DB1}"
remove_db "${DB2}"
unset DB1 DB2 ALIAS_DIR

## the following tests use the same layout
make_alias_db () {
    local ALIAS_DIR
    ALIAS_DIR=$(mktemp -d)
    printf ">a1\nMKVW\n" | \
        makeblastdb -dbtype prot -blastdb_version 4 -in - -title "vol1" \
                    -out "${ALIAS_DIR}/vol1" > /dev/null 2>&1
    printf ">b1\nMKVWW\n>b2\nMKVY\n" | \
        makeblastdb -dbtype prot -blastdb_version 4 -in - -title "vol2" \
                    -out "${ALIAS_DIR}/vol2" > /dev/null 2>&1
    printf "%s" "${1}" > "${ALIAS_DIR}/alias.pal"
    printf "%s/alias\n" "${ALIAS_DIR}"
}

DESCRIPTION="alias: title is read from the alias file"
DB=$(make_alias_db $'TITLE two volumes\nDBLIST vol1 vol2\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database title:    two volumes" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: base name is the title when TITLE is missing"
DB=$(make_alias_db $'DBLIST vol1 vol2\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database title:    ${DB}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: sequence and residue counts are summed"
DB=$(make_alias_db $'TITLE two volumes\nDBLIST vol1 vol2\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     13 residues in 3 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: longest sequence of all volumes"
DB=$(make_alias_db $'TITLE two volumes\nDBLIST vol1 vol2\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Longest db seq:    5 residues" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: hits from all volumes are reported"
DB=$(make_alias_db $'TITLE two volumes\nDBLIST vol1 vol2\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *3" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## ordinal ids are relative to each volume
DESCRIPTION="alias: dump all volumes"
DB=$(make_alias_db $'TITLE two volumes\nDBLIST vol1 vol2\n')
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    grep "^>" | \
    tr "\n" " " | \
    grep -qx ">gnl|BL_ORD_ID|0 a1 >gnl|BL_ORD_ID|0 b1 >gnl|BL_ORD_ID|1 b2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: a single volume"
DB=$(make_alias_db $'DBLIST vol2\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     9 residues in 2 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: volume names can be quoted"
DB=$(make_alias_db $'DBLIST "vol1" "vol2"\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     13 residues in 3 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: Windows line endings are accepted"
DB=$(make_alias_db $'TITLE two volumes\r\nDBLIST vol1 vol2\r\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     13 residues in 3 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: unknown lines are ignored"
DB=$(make_alias_db $'# comment\nFOO bar\nDBLIST vol1 vol2\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     13 residues in 3 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: missing volume fails"
DB=$(make_alias_db $'DBLIST vol1 vol3\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    grep -qx "Unable to open file $(dirname "${DB}")/vol3.pin." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: GILIST is not supported"
DB=$(make_alias_db $'DBLIST vol1\nGILIST vol1.gil\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    grep -qx "GILIST in database alias files not implemented." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## an alias file can refer to another alias file
DESCRIPTION="alias: nested alias files"
DB=$(make_alias_db $'TITLE two volumes\nDBLIST vol1 vol2\n')
printf "DBLIST alias\n" > "$(dirname "${DB}")/nested.pal"
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "$(dirname "${DB}")/nested" | \
    grep -qx "Database size:     13 residues in 3 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="alias: nested alias files (title of the outer file)"
DB=$(make_alias_db $'TITLE two volumes\nDBLIST vol1 vol2\n')
printf "TITLE outer\nDBLIST alias\n" > "$(dirname "${DB}")/nested.pal"
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "$(dirname "${DB}")/nested" | \
    grep -qx "Database title:    outer" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## nucleotide alias files have the extension .nal
DESCRIPTION="alias: nucleotide alias file (.nal)"
DB_DIR=$(mktemp -d)
printf ">n1\nACGTACGT\n" | \
    makeblastdb -dbtype nucl -blastdb_version 4 -in - -title "n1" \
                -out "${DB_DIR}/vol1" > /dev/null 2>&1
printf ">n2\nACGTACGTAA\n" | \
    makeblastdb -dbtype nucl -blastdb_version 4 -in - -title "n2" \
                -out "${DB_DIR}/vol2" > /dev/null 2>&1
printf "TITLE nucleotides\nDBLIST vol1 vol2\n" > "${DB_DIR}/alias.nal"
printf ">q1\nACGTACGT\n" | \
    "${SWIPE}" \
        --db "${DB_DIR}/alias" \
        --symtype 0 | \
    grep -qx "Database size:     18 residues in 2 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${DB_DIR}"
unset DB_DIR

DESCRIPTION="alias: protein alias file is ignored by nucleotide searches"
DB=$(make_alias_db $'DBLIST vol1 vol2\n')
printf ">q1\nACGT\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 2>&1 | \
    grep -qx "Unable to open file ${DB}.nin." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## an alias file takes precedence over an index file with the same
## base name
DESCRIPTION="alias: alias file takes precedence over a volume"
DB=$(printf ">s1\nMKV\n" | make_db prot)
DB2=$(printf ">t1\nMKVW\n>t2\nMKVW\n" | make_db prot)
for EXTENSION in pin phr psq ; do
    cp "${DB2}.${EXTENSION}" "$(dirname "${DB}")/other.${EXTENSION}"
done
printf "DBLIST other\n" > "${DB}.pal"
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     8 residues in 2 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
remove_db "${DB2}"
unset DB DB2 EXTENSION

DESCRIPTION="alias: many volumes (search is split into chunks per volume)"
DB_DIR=$(mktemp -d)
LIST=""
for ((i = 1 ; i <= 20 ; i++)) ; do
    printf ">s%d\nMKVW\n" ${i} | \
        makeblastdb -dbtype prot -blastdb_version 4 -in - -title "v${i}" \
                    -out "${DB_DIR}/vol${i}" > /dev/null 2>&1
    LIST="${LIST} vol${i}"
done
printf "DBLIST%s\n" "${LIST}" > "${DB_DIR}/alias.pal"
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB_DIR}/alias" \
        --num_threads 4 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *20" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -rf "${DB_DIR}"
unset DB_DIR LIST i


#*****************************************************************************#
#                                                                             #
#                      alias files: masked databases                          #
#                                                                             #
#*****************************************************************************#

## OIDLIST, MEMB_BIT, NSEQ, LENGTH and MAXOID define a subset of a
## volume (as in NCBI's swissprot, pdbaa or pdbnt). The mask file has
## a 4-byte header, followed by one bit per sequence (most
## significant bit first). Here, the mask selects only the second
## sequence of volume 2 (0x40 = 01000000). Selected sequences are
## reported only if their deflines carry the membership bit, which
## makeblastdb cannot set: their identifiers are empty.

make_masked_db () {
    local DB
    DB=$(make_alias_db "${1}")
    printf '\x00\x00\x00\x01\x40' > "$(dirname "${DB}")/vol2.msk"
    printf "%s\n" "${DB}"
}

MASKED=$'TITLE masked\nDBLIST vol2\nOIDLIST vol2.msk\nMEMB_BIT 1\nNSEQ 1\nLENGTH 4\nMAXOID 1\n'

DESCRIPTION="masked: title is read from the alias file"
DB=$(make_masked_db "${MASKED}")
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database title:    masked" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## counts are not computed, they are read from NSEQ and LENGTH
DESCRIPTION="masked: size is read from the alias file (NSEQ and LENGTH)"
DB=$(make_masked_db "${MASKED}")
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     4 residues in 1 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="masked: size is not checked (NSEQ and LENGTH are trusted)"
DB=$(make_masked_db $'DBLIST vol2\nOIDLIST vol2.msk\nMEMB_BIT 1\nNSEQ 1000\nLENGTH 99999\nMAXOID 1\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Database size:     99999 residues in 1000 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="masked: only selected sequences are searched"
DB=$(make_masked_db "${MASKED}")
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

DESCRIPTION="masked: selected sequence is the second sequence (MKVY)"
DB=$(make_masked_db "${MASKED}")
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <dseq>MKVY</dseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="masked: deflines without membership bit are not shown"
DB=$(make_masked_db "${MASKED}")
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 2 | \
    grep -qx "" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="masked: dump shows no sequence (no membership bit)"
DB=$(make_masked_db "${MASKED}")
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 < /dev/null | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## sequences beyond MAXOID are excluded
DESCRIPTION="masked: sequences beyond MAXOID are excluded"
DB=$(make_masked_db $'DBLIST vol2\nOIDLIST vol2.msk\nMEMB_BIT 1\nNSEQ 1\nLENGTH 4\nMAXOID 0\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="masked: missing mask file fails"
DB=$(make_alias_db $'DBLIST vol2\nOIDLIST vol2.msk\nMEMB_BIT 1\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    grep -qx "Unable to open msk file $(dirname "${DB}")/vol2.msk." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="masked: two volumes and a membership bit are rejected"
DB=$(make_masked_db $'DBLIST vol1 vol2\nOIDLIST vol2.msk\nMEMB_BIT 1\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" 2>&1 | \
    grep -qx "Illegal alias file (1)." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## nested masked alias files: the inner alias must list one volume
## and one mask
DESCRIPTION="masked: nested alias file with two volumes is rejected"
DB=$(make_masked_db $'DBLIST vol1 vol2\nOIDLIST vol2.msk\n')
printf "DBLIST alias\nMEMB_BIT 1\n" > "$(dirname "${DB}")/outer.pal"
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "$(dirname "${DB}")/outer" 2>&1 | \
    grep -qx "Illegal alias file (2)." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="masked: nested alias file with one volume and one mask"
DB=$(make_masked_db $'DBLIST vol2\nOIDLIST vol2.msk\nNSEQ 1\nLENGTH 4\nMAXOID 1\n')
printf "TITLE outer\nDBLIST alias\nMEMB_BIT 1\n" > "$(dirname "${DB}")/outer.pal"
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "$(dirname "${DB}")/outer" \
        --outfmt 7 | \
    grep -qx "      <dseq>MKVY</dseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## without a membership bit, the mask is ignored
DESCRIPTION="masked: mask is ignored without MEMB_BIT"
DB=$(make_masked_db $'DBLIST vol2\nOIDLIST vol2.msk\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="masked: membership bit is ignored without OIDLIST"
DB=$(make_masked_db $'DBLIST vol2\nMEMB_BIT 1\n')
printf ">q1\nMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB
unset MASKED


#*****************************************************************************#
#                                                                             #
#                         taxid lists (--taxid, -x)                           #
#                                                                             #
#*****************************************************************************#

## a list of taxonomic ids, one per line: only sequences with one of
## these taxids are searched

make_taxid_db () {
    printf ">s1\nMKV\n>s2\nMKVW\n>s3\nMKVY\n" | \
        make_db prot \
                -parse_seqids \
                -taxid_map <(printf "s1 9606\ns2 600000\ns3 10090\n")
}

DESCRIPTION="taxid: only sequences with a listed taxid are searched"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "9606\n") \
        --outfmt 8 | \
    cut -f 2 | \
    grep -qx "lcl|s1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="taxid: several taxids (one per line)"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "9606\n10090\n") \
        --outfmt 8 | \
    cut -f 2 | \
    sort | \
    tr "\n" " " | \
    grep -qx "lcl|s1 lcl|s3 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="taxid: several taxids (on one line)"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "9606 10090\n") \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## taxids are stored in a bitmap, initially large enough for
## taxids < 524,288, and extended as needed
DESCRIPTION="taxid: large taxid (600,000)"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "600000\n") \
        --outfmt 8 | \
    cut -f 2 | \
    grep -qx "lcl|s2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="taxid: unlisted taxid (no hits)"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "1\n") \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="taxid: empty taxid file (no hits)"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid /dev/null | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## sequences without taxid have the taxid 0
DESCRIPTION="taxid: sequences without taxid have taxid 0"
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

DESCRIPTION="taxid: database size is not updated"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "9606\n") | \
    grep -qx "Database size:     11 residues in 3 sequences" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## non-numerical values are rejected, with their line number (KI-25,
## see fixed_bugs.sh)
DESCRIPTION="taxid: a non-numerical value is rejected"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "9606\nabc\n10090\n") \
        --outfmt 8 2>&1 | \
    grep -q "^Illegal taxid on line 2 of taxid file " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="taxid: a non-numerical first value is rejected"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "abc\n9606\n") \
        --outfmt 8 2>&1 | \
    grep -q "^Illegal taxid on line 1 of taxid file " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="taxid: comma-separated values are rejected"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "9606,10090\n") \
        --outfmt 8 2>&1 | \
    grep -q "^Illegal taxid on line 1 of taxid file " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="taxid: all sequences with the same taxid (makeblastdb -taxid)"
DB=$(printf ">s1\nMKV\n>s2\nMKVW\n" | make_db prot -taxid 42)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "42\n") \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="taxid: dump only shows sequences with a listed taxid"
DB=$(make_taxid_db)
"${SWIPE}" \
    --db "${DB}" \
    --dump 1 \
    --taxid <(printf "10090\n") < /dev/null | \
    tr "\n" " " | \
    grep -qx ">lcl|s3 MKVY " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="taxid: works with several threads"
DB=$(make_taxid_db)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --taxid <(printf "9606\n10090\n") \
        --num_threads 3 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see known_issues.sh for very large taxid values


#*****************************************************************************#
#                                                                             #
#                                  valgrind                                   #
#                                                                             #
#*****************************************************************************#

if [[ "${VALGRIND_WORKS}" == "true" ]] ; then
    DB=$(make_alias_db $'TITLE two volumes\nDBLIST vol1 vol2\n')
    LOG=$(mktemp)
    printf ">q1\nMKVW\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" > /dev/null 2>&1
    DESCRIPTION="valgrind: alias database (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: alias database (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG

    DB=$(make_masked_db $'DBLIST vol2\nOIDLIST vol2.msk\nMEMB_BIT 1\nNSEQ 1\nLENGTH 4\nMAXOID 1\n')
    LOG=$(mktemp)
    printf ">q1\nMKVW\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" > /dev/null 2>&1
    DESCRIPTION="valgrind: masked database (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: masked database (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG

    DB=$(make_taxid_db)
    LOG=$(mktemp)
    printf ">q1\nMKV\n" | \
        valgrind \
            --log-file="${LOG}" \
            --leak-check=full \
            "${SWIPE}" \
            --db "${DB}" \
            --taxid <(printf "9606\n600000\n") > /dev/null 2>&1
    DESCRIPTION="valgrind: taxid list (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: taxid list (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG

    DB=$(printf ">s1\nACGTNNNNNNNNNNNNNNNNNNNNACGTRYKM\n>s2\nACG\n" | make_db nucl)
    LOG=$(mktemp)
    valgrind \
        --log-file="${LOG}" \
        --leak-check=full \
        "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --dump 1 < /dev/null > /dev/null 2>&1
    DESCRIPTION="valgrind: dump nucleotide database (no memory leak)"
    grep -q "in use at exit: 0 bytes" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    DESCRIPTION="valgrind: dump nucleotide database (no errors)"
    grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    rm -f "${LOG}"
    remove_db "${DB}"
    unset DB LOG
fi


exit 0
