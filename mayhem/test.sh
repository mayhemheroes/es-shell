#!/usr/bin/env bash
#
# mayhem/test.sh -- RUN the es-shell upstream functional test suite (built by
# mayhem/build.sh) and emit a CTRF summary. This is the project's OWN assertion
# suite (test/test.es + test/tests/*.es -- known-answer assertions over shell
# behavior), the same suite `make test` runs; it is NOT a corpus replay.
#
# It asserts behavior/output (each case runs es code and `assert`s the result), so
# neutering es to exit(0) makes the assertions fail -> this oracle fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -x ./es ] || [ ! -x ./testrun ]; then
  echo "test.sh: ./es or ./testrun missing -- build.sh did not produce the test binaries" >&2
  emit_ctrf "es-testsuite" 0 1 0
  exit 1
fi

# Run the suite in JUnit mode so we can parse per-case counts. test.es exits
# non-zero if any case failed; we still parse the XML for exact totals.
junit="$(mktemp)"
set +e
./es -ps < test/test.es --junit test/tests/* > "$junit" 2>/dev/null
run_rc=$?
set -e

# Tally <testsuite tests=".." failures=".." errors=".."> attribute counts. Some es
# test-case NAMES embed raw control bytes (e.g. an ESC in syntax.es), which is not
# well-formed XML -- so tally the testsuite tags by regex rather than a strict parse.
read -r PASSED FAILED < <(python3 - "$junit" <<'PY'
import re, sys
raw = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
tests = fails = 0
for tag in re.findall(r"<testsuite\b[^>]*>", raw):
    def attr(name):
        m = re.search(r'\b%s="(\d+)"' % name, tag)
        return int(m.group(1)) if m else 0
    tests += attr("tests")
    fails += attr("failures") + attr("errors")
print("%d %d" % (tests - fails, fails))
PY
)
rm -f "$junit"

PASSED="${PASSED:-0}"; FAILED="${FAILED:-0}"
# ZERO parsed cases means the suite did not actually run (e.g. es neutered and
# emitted nothing) -- that is a failure regardless of exit status; likewise a
# non-zero suite exit must fail even if the XML tally looks clean.
if [ "$(( PASSED + FAILED ))" -eq 0 ] || { [ "$run_rc" -ne 0 ] && [ "$FAILED" -eq 0 ]; }; then
  FAILED=$(( FAILED + 1 ))
fi

emit_ctrf "es-testsuite" "$PASSED" "$FAILED" 0
