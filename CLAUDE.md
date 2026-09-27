# `CLAUDE.md` - black-box tests for swipe


## The Golden Rule

When unsure about implementation details, ALWAYS ask the developer.


## Project Context

swipe is a tool for Smith-Waterman database searches with
inter-sequence SIMD parallelisation. This repository contains a
collection of bash scripts, one per topic or search mode (symbol
type). Each bash script contains a number of small, independent
tests. Tests are designed to be as concise and self-sufficient as
possible, with limited dependencies. The goal is to write tests to
cover: 1) the behaviour described in swipe's documentation (`README`,
`CHANGES`, and the help message `swipe -h`); 2) all the corner-cases
you can think of; and finally 3) oddities due to implementation
choices in swipe (code coverage metrics are used to detect these).

swipe only reads BLAST databases (format version 4). Databases are
created on-the-fly with `makeblastdb -blastdb_version 4` (NCBI
BLAST+), with the `make_db` helper function defined at the top of
each script.


### A Typical Test

```sh
DESCRIPTION="blastp: raw score is the sum of BLOSUM62 scores (MKV = 14)"
DB=$(printf ">s1\nMKV\n" | make_db prot)
printf ">q1\nMKV\n" | \
    "${SWIPE}" \
        --db "${DB}" \
        --outfmt 7 | \
    grep -qx "      <score>14</score>" && \
    success "${DESCRIPTION}" || \
        failure "${DESCRIPTION}"
remove_db "${DB}"
unset DB
```

- DESCRIPTION is the message describing the test. It needs to be
  short, informative, and helpful if the test were to fail
- functions `success` and `failure` add `PASS: ` or `FAIL: ` before
  the message (and use a green-red color-coding for readability)
- input data is created on-the-fly, usually with a `printf` command,
  and is as small as possible
- raw scores are reported in the simple XML output (`--outfmt 7`,
  `<score>`), bit scores and expect values in the tabular output
  (`--outfmt 8`)
- **pipe output directly** to the test command rather than capturing
  into a variable
- if you need to create temporary files, use `mktemp` and always clean
  up temporary files (and databases, with `remove_db`) at the end of
  each test
- **fold each swipe option on its own line**, indented by 8 spaces
  under `"${SWIPE}"`
- if you need to create variables for a test, always `unset` the
  variables at the end of the test
- swipe messages should not be visible when running the tests
- swipe prints the query id before parsing subject headers: when a
  test checks that a database is read correctly, check the whole
  line, not only its beginning

Note that the final part of the test should not be more complicated
than `A && B || C`.


## Code Style and Patterns

### Guidelines:

- **preserve test files you were not instructed to change**
- **preserve existing comments**
- **always ask a human for instruction** if you think a comment should
  be modified or removed, or if you think a non-target test file
  should be modified
- when the documentation and the actual behaviour of swipe differ,
  describe the case and **ask** for a human review
- tests pinning a bug go to `known_issues.sh`, with the number of the
  issue; once fixed, the test is updated and moved to `fixed_bugs.sh`
- tests should be able to run on macOS, which uses an old, out-dated
  version of bash. So limit yourself to common bash syntax and to
  common command-line tools


### Testing instructions

- create a new git branch, stemming from the `dev` branch, and using
  the naming pattern `tmp_$(date +%Y%m%d%H%M%S)`. When the tests go
  with a change in swipe (twin branches), both branches have **the
  same name** in swipe and swipe-tests: the CI of swipe tests each
  branch with the swipe-tests branch of the same name (or `dev` when
  there is none)
- run `bash ./scripts/<name>.sh ../swipe/swipe | grep "FAIL"` to run a
  test script
- note that `failure()` exits the script — test sequences must be
  reliable
- **all** tests should pass before you commit
- run `shellcheck ./scripts/<name>.sh` and fix all reported issues
- commit often, it is ok to have only a single test or a few tests per
  commit
- do not add "Co-Authored-By" trailers to commit messages.
- when done, ask for a human review. Humans are in charge of merging
  your work into the dev branch


## What AI Must always Do

AI must always leave these untouched:
1. **C++ files** - They encode human intent
2. **failure() and success() functions** - Seriously
3. **files outside the test repository** - Limit yourself to the starting directory
4. **comments** - They're there for a reason
5. **already existing tests** - They've been reviewed by a human

Remember: We prefer maintainability and readability over
cleverness. When in doubt, choose the boring solution or ask for help.
