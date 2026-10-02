# swipe-tests

test-suite for [SWIPE](https://github.com/torognes/swipe): rapid local
alignment searches in amino acid or nucleotide sequence databases

The objective is to gather, organize and factorize all the scripts
written to test the behaviour, results or bugs of swipe. Tests are
small, independent black-box tests written in bash.

Tests are grouped into:
- general tests: command-line options (`options.sh`), query input
  (`query.sh`), databases, alias files, masks, taxid lists and dumps
  (`database.sh`), and output formats (`output.sh`),
- one script per symbol type (search mode): `blastn.sh` (`-p 0`),
  `blastp.sh` (`-p 1`), `blastx.sh` (`-p 2`), `tblastn.sh` (`-p 3`),
  `tblastx.sh` (`-p 4`), and `sound.sh` (`-p 5`, undocumented),
- regression tests for the bugs listed in swipe's CHANGES file
  (`fixed_bugs.sh`),
- tests pinning the current behaviour of known issues
  (`known_issues.sh`). These tests are expected to fail when an issue
  is fixed, and should then be updated.

To test a new version of swipe, simply launch:
```sh
bash run_all_tests.sh ../swipe/swipe
```

(tests use the first swipe binary in `$PATH` by default). The run
stops at the first failure, and always ends with a verdict line:
`SUMMARY: OK - all 12 test scripts completed`, or `SUMMARY: ABORTED -
stopped in scripts/<name>.sh (test script number N)`.

To run a single test script:
```sh
bash ./scripts/blastp.sh ../swipe/swipe
```

Large databases (more than 2^31 residues in a volume, offsets above
2^31, more than 2^32 residues in all) are tested by a separate script,
not run by `run_all_tests.sh`: it writes about 9 GB of temporary files
and takes a few minutes (the optional second argument is the directory
for the temporary files, `${TMPDIR}` by default):
```sh
bash ./scripts/large_databases.sh ../swipe/swipe [directory]
```

Requirements:
- bash version 4 or higher,
- [makeblastdb](https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/)
  (NCBI BLAST+), used to create small databases on-the-fly (option
  `-blastdb_version 4`),
- common command-line tools (`awk`, `sed`, `grep`, `dd`, `od`, ...).

Optionally:
- [valgrind](http://valgrind.org/) (memory leaks and errors),
- a swipe binary built with the address sanitizer, to activate
  additional checks:
```sh
make swipe CXXFLAGS="-g -O1 -fsanitize=address,undefined" \
     LINKFLAGS="-fsanitize=address,undefined"
```
