#!/bin/bash -
# shellcheck disable=SC2015

export LC_ALL=C  # use US/EN decimal separator (.)

## Print a header
SCRIPT_NAME="output formats"
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

## a database with a long description, a gi number and a taxid, and
## a short sequence without description
make_output_db () {
    printf ">gi|123|sp|P12345|NAME_HUMAN %s\nMKVLAAGIVGLLLAW\n>s2\nMKV\n" \
           "a very long description that will certainly be truncated in the list of hits" | \
        make_db prot -parse_seqids -taxid 9606
}

## output formats (--outfmt, -m):
##  0: plain text (default)
##  7: simple XML
##  8: tab-separated values
##  9: tab-separated values with comment lines
## 99: ParAlign XML (undocumented)


#*****************************************************************************#
#                                                                             #
#                       plain text output (--outfmt 0)                        #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="plain: first line is the program name and version (no build date)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    head -n 1 | \
    grep -Eqx "SWIPE [0-9]+[.][0-9]+[.][0-9]+" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: the reference is printed"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "with inter-sequence SIMD parallelisation, BMC Bioinformatics, 12:221." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: search progress line"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Searching..................................................done" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: search start time (UTC)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -Eqx "Search started:    [A-Z][a-z]{2}, [ 0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9:]{8} UTC" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: search completion time (UTC)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -Eqx "Search completed:  [A-Z][a-z]{2}, [ 0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9:]{8} UTC" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: elapsed time"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -Eqx "Elapsed:           [0-9]+[.][0-9]{2}s" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the elapsed time is measured with a monotonic clock; the speed is
## "n/a" if no time elapsed (KI-33, see fixed_bugs.sh)
DESCRIPTION="plain: search speed"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -Eqx "Speed:             ([0-9]+[.][0-9]{3} GCUPS|n/a)" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: header of the list of hits (with statistics)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "Sequences producing significant alignments:                      (bits) Value" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: header of the list of hits (without statistics)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 3 \
        --gapextend 3 | \
    grep -qx "Sequences producing significant alignments:                         Score" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## descriptions are truncated to 67 characters (with "...") in the
## list of hits
DESCRIPTION="plain: list of hits, long descriptions are truncated"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "sp|P12345|NAME_HUMAN a very long description that will certainly...    33   4e-08" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: list of hits, short descriptions are padded"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "lcl|s2                                                                 10   0.26 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: list of hits, raw scores without statistics"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 3 \
        --gapextend 3 | \
    grep -qx "lcl|s2                                                                 14" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## expect values are printed with different formats: 0.0 below
## 1e-180, 'e-116' below 9.5e-100 (the leading digit is dropped, as in
## BLAST), exponential below 0.00095, then 3, 2, 1 or 0 decimals
while read -r LENGTH EXPECTED ; do
    DESCRIPTION="plain: expect value format (${EXPECTED})"
    DB=$(printf ">s1\n%s\n" "$(repeat MKVLAAGIVW "${LENGTH}")" | make_db prot)
    printf ">q1\n%s\n" "$(repeat MKVLAAGIVW "${LENGTH}")" | \
        "${SWIPE}" \
            --db "${DB}" | \
        grep "^ Score = " | \
        sed 's/.*Expect = //' | \
        sed 's/ *$//' | \
        grep -qxF "${EXPECTED}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
50 0.0
20 e-116
7 7e-40
EOF
unset LENGTH EXPECTED

while read -r QUERY DBSIZE EXPECTED ; do
    DESCRIPTION="plain: expect value format (${EXPECTED})"
    DB=$(printf ">s1\nMKVLAAGIVGLLLAW\n" | make_db prot)
    printf ">q1\n%s\n" "${QUERY}" | \
        "${SWIPE}" \
            --db "${DB}" \
            --evalue 1e9 \
            --dbsize "${DBSIZE}" | \
        grep "^ Score = " | \
        sed 's/.*Expect = //' | \
        sed 's/^ *//; s/ *$//' | \
        grep -qxF "${EXPECTED}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
MKVLAAG 0 8e-04
MKVLA 0 0.009
MKV 100 0.29
MKV 1000 2.9
MKV 10000 29
MKV 1000000 2928
EOF
unset QUERY DBSIZE EXPECTED

DESCRIPTION="plain: large expect values are right-aligned"
DB=$(printf ">s1\nMKVLAAGIVGLLLAW\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --evalue 1e9 \
        --dbsize 10000 | \
    grep -qx " Score = 10.0 bits (14), Expect =    29" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: alignment header, long deflines are wrapped"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -A 1 -x ">sp|P12345|NAME_HUMAN a very long description that will certainly be truncated " | \
    tail -n 1 | \
    grep -qx "           in the list of hits                                                 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: alignment header, subject length"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -m 1 "Length = " | \
    grep -qx "          Length = 15" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: alignment header, bit score, raw score and expect value"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -m 1 "^ Score = " | \
    grep -qx " Score = 32.7 bits (73), Expect = 4e-08" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: alignments are wrapped every 60 residues"
DB=$(printf ">s1\n%s\n" "$(repeat MKVLAAGIVW 7)" | make_db prot)
printf ">q1\n%s\n" "$(repeat MKVLAAGIVW 7)" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep "^Query: " | \
    tr "\n" " " | \
    grep -qx "Query:  1 $(repeat MKVLAAGIVW 6) 60 Query: 61 MKVLAAGIVW 70 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: alignment of exactly 60 residues fits in one block"
DB=$(printf ">s1\n%s\n" "$(repeat MKVLAAGIVW 6)" | make_db prot)
printf ">q1\n%s\n" "$(repeat MKVLAAGIVW 6)" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -c "^Query: " | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: position width adapts to the largest position"
DB=$(printf ">s1\n%s\n" "$(repeat MKVLAAGIVW 11)" | make_db prot)
printf ">q1\n%s\n" "$(repeat MKVLAAGIVW 11)" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -m 1 "^Sbjct: " | \
    grep -qx "Sbjct:   1 $(repeat MKVLAAGIVW 6) 60" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: no hits"
DB=$(make_output_db)
printf ">q1\nPPPP\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -qx "No hits." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="plain: no hits (no list header)"
DB=$(make_output_db)
printf ">q1\nPPPP\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "^Sequences producing" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                          simple XML (--outfmt 7)                            #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="XML: first line is the XML declaration"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    head -n 1 | \
    grep -qx '<?xml version="1.0"?>' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="XML: no program header"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -q "^SWIPE" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the results of all queries are inside one root element (KI-26,
## fixed in 2.2.0; each <result> was a root element)
DESCRIPTION="XML: result element inside the results root element"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    sed -n '2p;3p;$p' | \
    tr "\n" " " | \
    grep -qx "<results> <result> </results> " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="XML: number of hits"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "    <hitcount>2</hitcount>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## hitcount is the number of hits kept (the largest of -v and -b),
## not the number of hits found
DESCRIPTION="XML: number of hits is limited by -v and -b"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 1 \
        --num_alignments 1 \
        --outfmt 7 | \
    grep -qx "    <hitcount>1</hitcount>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

while read -r ELEMENT ; do
    DESCRIPTION="XML: first hit, ${ELEMENT}"
    DB=$(make_output_db)
    printf ">q1 desc\nMKVLAAGIVGLLLAW\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --outfmt 7 | \
        grep -qxF "      ${ELEMENT}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
<hitno>1</hitno>
<track>0</track>
<query>q1</query>
<name>sp|P12345|NAME_HUMAN a very long description that will certainly be truncated in the list of hits</name>
<len>15</len>
<score>73</score>
<alignment>M15</alignment>
<qpos>1,15</qpos>
<dpos>1,15</dpos>
<qseq>MKVLAAGIVGLLLAW</qseq>
<aseq>|||||||||||||||</aseq>
<dseq>MKVLAAGIVGLLLAW</dseq>
EOF
unset ELEMENT

DESCRIPTION="XML: track is the database ordinal number"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep "<track>" | \
    tr -d " " | \
    tr "\n" " " | \
    grep -qx "<track>0</track> <track>1</track> " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="XML: positives are marked with '+'"
DB=$(printf ">s1\nMKVWMKVW\n" | make_db prot)
printf ">q1\nMKIWMKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <aseq>||+|||||</aseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="XML: mismatches are marked with a space"
DB=$(printf ">s1\nMKVWMKVW\n" | make_db prot)
printf ">q1\nMKVWAKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <aseq>|||| |||</aseq>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="XML: hits beyond --num_alignments have no alignment"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 1 \
        --outfmt 7 | \
    grep -c "<alignment>" | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="XML: hits are limited by --num_descriptions"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 1 \
        --outfmt 7 | \
    grep -c "<hit>" | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="XML: no hits (empty hits element)"
DB=$(make_output_db)
printf ">q1\nPPPP\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    tr -d " \n" | \
    grep -qx '<?xmlversion="1.0"?><results><result><general><hitcount>0</hitcount></general><hits></hits></result></results>' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="XML: query without description (empty query element)"
DB=$(make_output_db)
printf "MKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -m 1 "<query>" | \
    grep -qx "      <query></query>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see known_issues.sh (KI-26) for several queries, and fixed_bugs.sh
## (KI-27) for special characters


#*****************************************************************************#
#                                                                             #
#                     tab-separated values (--outfmt 8)                       #
#                                                                             #
#*****************************************************************************#

## fields: query id, subject id, % identity, alignment length,
## mismatches, gap openings, q. start, q. end, s. start, s. end,
## e-value, bit score

DESCRIPTION="TSV: 12 tab-separated fields"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    awk -F "\t" '{if (NF != 12) {exit 1}}' && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV: first hit"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    head -n 1 | \
    grep -qx "q1	gi|123|sp|P12345|NAME_HUMAN	100.00	15	0	0	1	15	1	15	3.8e-08	32.7" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV: no header line"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "^#" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV: subject id without description"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 2 | \
    grep -q " " && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## gi numbers are always shown in tabular output, even without -I
DESCRIPTION="TSV: gi numbers are always shown"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 2 | \
    grep -qx "gi|123|sp|P12345|NAME_HUMAN" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV: mismatches and identity"
DB=$(printf ">s1\nMKVWMKVW\n" | make_db prot)
printf ">q1\nMKVWAKVW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 3-6 | \
    grep -qx "87.50	8	1	0" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## gap positions are not mismatches
DESCRIPTION="TSV: gaps are not counted as mismatches"
DB=$(printf ">s1\nMKVLAAGIVGLLLAWHHHHHKLMNPQRSTVWY\n" | make_db prot)
printf ">q1\nMKVLAAGIVGLLLAWKLMNPQRSTVWY\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 4-6 | \
    grep -qx "32	0	1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV: large expect values in exponential notation"
DB=$(printf ">s1\nMKVLAAGIVGLLLAW\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --evalue 1e9 \
        --dbsize 1000000 \
        --outfmt 8 | \
    cut -f 11 | \
    grep -qx "2.9e+03" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV: no hits (empty output)"
DB=$(make_output_db)
printf ">q1\nPPPP\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## the number of lines is limited by --num_alignments, not by
## --num_descriptions
DESCRIPTION="TSV: lines are limited by --num_alignments"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 1 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV: lines are not limited by --num_descriptions"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 1 \
        --outfmt 8 | \
    wc -l | \
    grep -qx " *2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV: --num_alignments 0 (empty output)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 0 \
        --outfmt 8 | \
    grep -q "." && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV: several queries"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    cut -f 1 | \
    tr "\n" " " | \
    grep -qx "q1 q1 q2 q2 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#              tab-separated values with comments (--outfmt 9)                #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="TSV+: four comment lines per query"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 9 | \
    grep -c "^# " | \
    grep -qx "4" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV+: first comment line (program, version, reference, no build date)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 9 | \
    head -n 1 | \
    grep -Eqx "# SWIPE [0-9.]+ - Reference: T. Rognes \(2011\) .*, 12:221." && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV+: query comment line"
DB=$(make_output_db)
printf ">q1 some description\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 9 | \
    grep -qx "# Query: q1 some description" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV+: database comment line"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 9 | \
    grep -qx "# Database: ${DB}" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV+: fields comment line (with statistics)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 9 | \
    grep -qx "# Fields: Query id, Subject id, % identity, alignment length, mismatches, gap openings, q. start, q. end, s. start, s. end, e-value, bit score" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV+: fields comment line (without statistics)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --gapopen 3 \
        --gapextend 3 \
        --outfmt 9 | \
    grep -qx "# Fields: Query id, Subject id, % identity, alignment length, mismatches, gap openings, q. start, q. end, s. start, s. end, score" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV+: same hits as --outfmt 8"
DB=$(make_output_db)
diff \
    <(printf ">q1\nMKVLAAGIVGLLLAW\n" | \
          "${SWIPE}" \
              --db "${DB}" \
              --outfmt 8) \
    <(printf ">q1\nMKVLAAGIVGLLLAW\n" | \
          "${SWIPE}" \
              --db "${DB}" \
              --outfmt 9 | \
          grep -v "^#") > /dev/null && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV+: comment lines are printed even without hits"
DB=$(make_output_db)
printf ">q1\nPPPP\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 9 | \
    grep -c "^# " | \
    grep -qx "4" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="TSV+: comment lines are printed for each query"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 9 | \
    grep -c "^# Query: " | \
    grep -qx "2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB


#*****************************************************************************#
#                                                                             #
#                   ParAlign XML (--outfmt 99, undocumented)                  #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="ParAlign XML: XML declaration and root element"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    head -n 2 | \
    tail -n 1 | \
    grep -q "^<ParalignXML xmlns:xsi=" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: last line closes the root element"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    tail -n 1 | \
    grep -qx "</ParalignXML>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: one root element for several queries"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -c "<ParalignXML" | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: one paralignOutput element per query"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n>q2\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -c "<paralignOutput>" | \
    grep -qx "2" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: no query (root element only)"
DB=$(make_output_db)
printf "" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 99 | \
    grep -c "paralignOutput>" | \
    grep -qx "0" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

while read -r ELEMENT ; do
    DESCRIPTION="ParAlign XML: ${ELEMENT}"
    DB=$(make_output_db)
    printf ">q1 desc\nMKVLAAGIVGLLLAW\n" | \
        "${SWIPE}" \
            --db "${DB}" \
            --outfmt 99 | \
        grep -qF "${ELEMENT}" && \
        success "${DESCRIPTION}" || \
            failure "${DESCRIPTION}"
    remove_db "${DB}"
    unset DB
done <<EOF
<programName>swipe</programName>
<queryFilename>-</queryFilename>
<querySequencetype>Amino Acid</querySequencetype>
<queryDescription>q1 desc</queryDescription>
<queryLength>15</queryLength>
<querySequence>MKVLAAGIVGLLLAW</querySequence>
<databaseSequencetype>Amino Acid</databaseSequencetype>
<databaseDescription>test</databaseDescription>
<databaseVersion>4</databaseVersion>
<residueCount>18</residueCount>
<sequenceCount>2</sequenceCount>
<longestSequenceLength>15</longestSequenceLength>
<algorithm>Smith-Waterman</algorithm>
<scoreMatrix>BLOSUM62</scoreMatrix>
<gapPenaltyOpen>11</gapPenaltyOpen>
<gapPenaltyExtension>1</gapPenaltyExtension>
<gappedLambda>0.267</gappedLambda>
<expectRangeFrom>0</expectRangeFrom>
<expectRangeTo>10</expectRangeTo>
<hitLimit>250</hitLimit>
<alignmentLimit>100</alignmentLimit>
<subalignmentLimit>1</subalignmentLimit>
<threads>1</threads>
<totalCount>2</totalCount>
<shownCount>2</shownCount>
<alignmentCount>2</alignmentCount>
<shortVersionAnchor>0_0____</shortVersionAnchor>
<shortVersionLinkText>gi|123</shortVersionLinkText>
<shortVersionLinkText>sp|P12345|NAME_HUMAN</shortVersionLinkText>
<shortVersionName>a very long description that will c</shortVersionName>
<shortVersionScore>73</shortVersionScore>
<shortVersionEValue>3.8e-08</shortVersionEValue>
<databaseSequenceLength>15 aa</databaseSequenceLength>
<longVersionScore>73</longVersionScore>
<identicalNominator>15</identicalNominator>
<identicalPercentage>100.0</identicalPercentage>
<positiveNominator>15</positiveNominator>
<indelsNominator>0</indelsNominator>
<alignmentQueryStart>1</alignmentQueryStart>
<alignmentQueryLine>MKVLAAGIVGLLLAW</alignmentQueryLine>
<alignmentQueryEnd>15</alignmentQueryEnd>
<alignmentDatabaseLine>MKVLAAGIVGLLLAW</alignmentDatabaseLine>
EOF
unset ELEMENT

## the query file name is shown as given (KI-32, see fixed_bugs.sh)
DESCRIPTION="ParAlign XML: query file name is shown as given"
DB=$(make_output_db)
QUERY=$(mktemp)
printf ">q1\nMKV\n" > "${QUERY}"
"${SWIPE}" \
    --db "${DB}" \
    --query "${QUERY}" \
    --outfmt 99 | \
    grep -qF "<queryFilename>${QUERY}</queryFilename>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
rm -f "${QUERY}"
remove_db "${DB}"
unset DB QUERY

DESCRIPTION="ParAlign XML: --num_alignments limits long version hits"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 1 \
        --outfmt 99 | \
    grep -c "<longVersionHit>" | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: --num_alignments 0 (no long version hits)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_alignments 0 \
        --outfmt 99 | \
    grep -q "<longVersionHits>" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: --num_descriptions limits short version hits"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --num_descriptions 1 \
        --outfmt 99 | \
    grep -c "<shortVersionHit>" | \
    grep -qx "1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: nucleotide search (score matrix NT)"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --outfmt 99 | \
    grep -q "<scoreMatrix>NT</scoreMatrix>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: nucleotide search (query strands)"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --outfmt 99 | \
    grep -q "<queryStrands>Both</queryStrands>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: nucleotide search (plus strand)"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 99 | \
    grep -q "<alignmentMatchLocation>Matches on same strands.</alignmentMatchLocation>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: nucleotide search (length in nt)"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 99 | \
    grep -q "<databaseSequenceLength>10 nt</databaseSequenceLength>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: nucleotide search (no positives)"
DB=$(printf ">s1\nACGTACGTAC\n" | make_db nucl)
printf ">q1\nACGTACGTAC\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 0 \
        --strand 1 \
        --outfmt 99 | \
    grep -q "<positive>" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see fixed_bugs.sh (KI-29) for minus-strand hits

DESCRIPTION="ParAlign XML: blastx search (query frame)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --num_descriptions 1 \
        --num_alignments 1 \
        --outfmt 99 | \
    tr -d "\t\n" | \
    grep -q "<longVersionQueryFrame><queryStrand>+</queryStrand><queryFrame>1</queryFrame></longVersionQueryFrame>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: blastx search (short version frame)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --num_descriptions 1 \
        --num_alignments 1 \
        --outfmt 99 | \
    grep -q "<shortVersionFrame>+1</shortVersionFrame>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: blastx search (anchor)"
DB=$(printf ">p1\nMKVLAW\n" | make_db prot)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 2 \
        --num_descriptions 1 \
        --num_alignments 1 \
        --outfmt 99 | \
    grep -q "<shortVersionAnchor>0_0_1_+__</shortVersionAnchor>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: tblastn search (database frame)"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --num_descriptions 1 \
        --num_alignments 1 \
        --outfmt 99 | \
    tr -d "\t\n" | \
    grep -q "<longVersionDatabaseFrame><databaseStrand>+</databaseStrand><databaseFrame>3</databaseFrame></longVersionDatabaseFrame>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: tblastn search (anchor)"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nMKVLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 3 \
        --num_descriptions 1 \
        --num_alignments 1 \
        --outfmt 99 | \
    grep -q "<shortVersionAnchor>0_0___3_+</shortVersionAnchor>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: tblastx search (frames)"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --num_descriptions 1 \
        --num_alignments 1 \
        --outfmt 99 | \
    grep -q "<shortVersionFrame>-1/-3</shortVersionFrame>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="ParAlign XML: tblastx search (anchor)"
DB=$(printf ">n1\nGGATGAAAGTTCTGGCTTGGCC\n" | make_db nucl)
printf ">q1\nATGAAAGTTCTGGCTTGG\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --symtype 4 \
        --num_descriptions 1 \
        --num_alignments 1 \
        --outfmt 99 | \
    grep -q "<shortVersionAnchor>0_0_1_-_3_-</shortVersionAnchor>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## see fixed_bugs.sh (KI-28) for search times


#*****************************************************************************#
#                                                                             #
#                  gi numbers (--show_gis) and taxids (--show_taxid)          #
#                                                                             #
#*****************************************************************************#

DESCRIPTION="--show_gis: gi numbers are hidden by default (plain)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -q "gi|123" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_gis: gi numbers are shown (plain, list of hits)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_gis | \
    grep -q "^gi|123|sp|P12345|NAME_HUMAN a very long description that will ce...    33" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_gis: gi numbers are shown (plain, alignments)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_gis | \
    grep -q "^>gi|123|sp|P12345|NAME_HUMAN a very long" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_gis: gi numbers are hidden by default (XML)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -q "<name>sp|P12345|NAME_HUMAN " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_gis: gi numbers are shown (XML)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_gis \
        --outfmt 7 | \
    grep -q "<name>gi|123|sp|P12345|NAME_HUMAN " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

## a sequence identified only by a gi number has an empty identifier
## when gi numbers are hidden
DESCRIPTION="--show_gis: gi-only identifier is empty by default"
DB=$(printf ">gi|456 gi only\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" | \
    grep -Eqx "gi only +10 +0.009" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_taxid: taxids are hidden by default"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 8 | \
    grep -q "taxid" && \
    failure "${DESCRIPTION}" || \
        success "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_taxid: taxids are appended to identifiers (TSV)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_taxid \
        --outfmt 8 | \
    cut -f 2 | \
    tr "\n" " " | \
    grep -qx "gi|123|sp|P12345|NAME_HUMAN|taxid|9606 lcl|s2|taxid|9606 " && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_taxid: taxids are appended to identifiers (plain)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_taxid | \
    grep -q "^>sp|P12345|NAME_HUMAN|taxid|9606 a very long" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_taxid: taxids are appended to identifiers (XML)"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_taxid \
        --outfmt 7 | \
    grep -qx "      <name>lcl|s2|taxid|9606</name>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_taxid: sequences without taxid are not changed"
DB=$(printf ">s1\nMKV\n" | make_db prot -parse_seqids)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_taxid \
        --outfmt 8 | \
    cut -f 2 | \
    grep -qx "lcl|s1" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB

DESCRIPTION="--show_gis and --show_taxid combined"
DB=$(make_output_db)
printf ">q1\nMKVLAAGIVGLLLAW\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --show_gis \
        --show_taxid | \
    grep -q "^>gi|123|sp|P12345|NAME_HUMAN|taxid|9606 a very long" && \
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
    for OUTFMT in 0 7 8 9 99 ; do
        DB=$(make_output_db)
        LOG=$(mktemp)
        printf ">q1\nMKVLAAGIVGLLLAW\n>q2\nMKV\n" | \
            valgrind \
                --log-file="${LOG}" \
                --leak-check=full \
                "${SWIPE}" \
                --db "${DB}" \
                --show_gis \
                --show_taxid \
                --num_alignments 1 \
                --outfmt "${OUTFMT}" > /dev/null 2>&1
        DESCRIPTION="valgrind: --outfmt ${OUTFMT} (no memory leak)"
        grep -q "in use at exit: 0 bytes" "${LOG}" && \
            success "${DESCRIPTION}" || \
                failure "${DESCRIPTION}"
        DESCRIPTION="valgrind: --outfmt ${OUTFMT} (no errors)"
        grep -q "ERROR SUMMARY: 0 errors" "${LOG}" && \
            success "${DESCRIPTION}" || \
                failure "${DESCRIPTION}"
        rm -f "${LOG}"
        remove_db "${DB}"
        unset DB LOG
    done
    unset OUTFMT
fi


exit 0
