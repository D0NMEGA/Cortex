# Deferred items from Plan 09-05

## Cosmetic: `download_indy.py` prints the session id twice on every failure

Observed while capturing the Task 2 negative-control transcripts. `main()` formats a caught
`ValueError` as `f"{session.get('id', '?')}: {exc}"`, but every message `_check_payload` raises
already begins with the session id, so stderr reads:

```
indy_20160915_01: indy_20160915_01: size mismatch - expected 106555127 bytes, got 106555000 ...
```

Purely cosmetic: the diagnostic content, the exit code, and every gate are correct, and the
transcripts in `09-ingest-evidence.md` record the real output rather than a cleaned-up version.

Not fixed here because `Decoder/scripts/download_indy.py` is outside this plan's declared
`files_modified` and is owned by Plan 09-01, which ran in a concurrent wave. The fix is a one-line
change (drop the id prefix from either the raise sites or the `main()` formatter, not both) and
should be folded into whichever later plan next touches that script. Note that
`Decoder/tests/test_download_integrity.py` asserts on message substrings, so the fix must keep the id
present in exactly one place.
