#!/usr/bin/env bash
#
# mayhem/build.sh -- build the es-shell fuzz harness + standalone reproducer, and
# the project's own test suite (built here, RUN by mayhem/test.sh).
#
# es is a GNU-autotools C project. We build twice from the same tree:
#   1) a sanitized build of every es object; the harness (mayhem/fuzz_es.c, an
#      in-process libFuzzer driver over parsestring()) is linked against all es
#      objects EXCEPT main.o/dump.o -> /mayhem/es (target name preserved) and a
#      standalone run-once reproducer -> /mayhem/fuzz_es-standalone.
#   2) a clean, NORMAL-flags build of `es` + `testrun` left in the source tree so
#      test.sh can run the upstream functional suite (`./es -s < test/test.es ...`).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS

# SanitizerCoverage must be baked into the es objects at COMPILE time (not just at the
# final link) or the in-process fuzzer gets no edge feedback (0 edges). -fsanitize=
# fuzzer-no-link instruments every object; the ASan runtime supplies weak no-op cov
# callbacks so the unused es/esdump binaries this build also links still resolve, while
# the harness is linked with the real libFuzzer runtime ($LIB_FUZZING_ENGINE) below.
FUZZ_COV="-fsanitize=fuzzer-no-link"

cd "$SRC"

# Generate the configure script from the repo (INSTALL: libtoolize -qi && autoreconf).
libtoolize -qi
autoreconf

# ---------------------------------------------------------------------------
# 1) Sanitized build of all es objects, then link the harness.
#    Build the PROJECT ITSELF (not just the harness) with $SANITIZER_FLAGS so the
#    fuzzed parser code is instrumented; $DEBUG_FLAGS carries DWARF < 4.
# ---------------------------------------------------------------------------
./configure --without-readline CC="$CC"
make -j"$MAYHEM_JOBS" es \
	ADDCFLAGS="$SANITIZER_FLAGS $FUZZ_COV $DEBUG_FLAGS" \
	ADDLDFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"

# All es objects except the CLI entry points (main.o -> es(1), dump.o -> esdump).
mapfile -t ES_OBJS < <(ls ./*.o | grep -Ev '/(main|dump)\.o$')

# Compile the harness against the sanitized es build (instrumented too).
$CC $SANITIZER_FLAGS $FUZZ_COV $DEBUG_FLAGS -I. -I"$SRC" \
	-c "$SRC/mayhem/fuzz_es.c" -o "$SRC/mayhem/fuzz_es.o"

# libFuzzer target binary (Mayhem target name is preserved as "es" in the Mayhemfile).
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
	"$SRC/mayhem/fuzz_es.o" "${ES_OBJS[@]}" -o /mayhem/fuzz_es

# Standalone (non-fuzzer) run-once reproducer for the same harness.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" \
	"$SRC/mayhem/fuzz_es.o" "${ES_OBJS[@]}" -o /mayhem/fuzz_es-standalone

# ---------------------------------------------------------------------------
# 2) Clean NORMAL-flags build of es + testrun for the functional test suite.
# ---------------------------------------------------------------------------
make clean
./configure --without-readline CC="$CC"
make -j"$MAYHEM_JOBS" es testrun

echo "build.sh: done -> /mayhem/fuzz_es, /mayhem/fuzz_es-standalone, $SRC/es (test), $SRC/testrun"
