/* fuzz_es.c -- in-process libFuzzer harness for the es-shell parser.
 *
 * The upstream Mayhem target ran the shell on a file (`es @@`), which EXECUTES
 * arbitrary shell code (fork/exec/hangs/filesystem side effects) — unsafe and
 * non-deterministic for fuzzing. This harness drives the SAME lexer/parser/tree
 * builder code path (token.c / y.tab.c / parse.y / input.c parsestring) purely
 * in process, with no evaluation, so it is deterministic and gets SanitizerCoverage
 * edges. The Mayhem target name (`es`) is preserved so run history is not orphaned.
 */

#include "es.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static Boolean es_initialized = FALSE;

static void ensure_init(void) {
	if (es_initialized)
		return;
	initconv();	/* %-conversion table used by str()/error formatting */
	initgc();	/* garbage collector -- "must be called at the dawn of time" */
	es_initialized = TRUE;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	char *s;

	ensure_init();

	/* parsestring() consumes a NUL-terminated C string. */
	s = (char *) malloc(size + 1);
	if (s == NULL)
		return 0;
	if (size != 0)
		memcpy(s, data, size);
	s[size] = '\0';

	ExceptionHandler
		parsestring(s);
	CatchException (e)
		/* Parse/lex errors (and other thrown es exceptions) are the
		 * expected outcome for most inputs -- swallow them. */
		(void) e;
	EndExceptionHandler

	free(s);
	return 0;
}
