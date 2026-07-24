#!/usr/bin/env bash
#
# tandem secret tripwire — fail if key material was committed anywhere in the
# repository. Runs over the WHOLE tree (including .github/**); only this scanner
# file is excluded, so the rest of .github is still covered.
#
# The search pattern is assembled from fragments at runtime so this scanner can
# never match itself.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

begin='BEGIN'
priv='PRIVATE KEY'
ts_prefix='ts''key-' # split so the literal never appears in this file
pattern="${begin} (RSA|OPENSSH|EC|DSA|PGP) ${priv}|${ts_prefix}[A-Za-z0-9]{6,}"

self='deploy/ci/secret-scan.sh'

if git grep -nIE "$pattern" -- . ":!${self}"; then
  echo "secret-scan: FAIL — potential key material committed (see matches above)" >&2
  exit 1
fi

echo "secret-scan: PASS — no committed key material"
