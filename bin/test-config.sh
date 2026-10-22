#!/usr/bin/env bash
#
# Tests for load_config / save_config in lib.sh.
#
# Every test uses a throwaway config repo under mktemp, never the real
# local/config.env. (A test email once leaked into the real config.env and was
# used for every commit for months. This file guards against that happening again.)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_CONFIG="$SCRIPT_DIR/../local/config.env"
real_before="$( [[ -f "$REAL_CONFIG" ]] && shasum "$REAL_CONFIG" || echo absent )"

failures=0
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; failures=$((failures + 1)); }

# Run a test body in a clean subshell with a fresh temp config repo.
# Clears any JACKS_NIX_* vars inherited from the caller first.
in_sandbox() {
  local name="$1"; shift
  local repo
  repo="$(mktemp -d)"
  if (
    unset $(compgen -v JACKS_NIX_) 2>/dev/null
    source "$SCRIPT_DIR/lib.sh"
    "$@" "$repo"
  ) </dev/null >"$repo.log" 2>&1; then
    pass "$name"
  else
    fail "$name"
    sed 's/^/    /' "$repo.log"
  fi
  rm -rf "$repo" "$repo.log"
}

saved_value() {  # repo key -> value from config.env, as sourcing would see it
  ( source "$1/local/config.env" && printf '%s' "${!2}" )
}

# --- tests ---------------------------------------------------------------

test_roundtrip_special_chars() {
  local repo="$1" tricky='J "Q" $HOME `x` back\slash'
  export JACKS_NIX_GIT_NAME="$tricky"
  load_config "$repo" install && save_config "$repo" || return 1
  [[ "$(saved_value "$repo" JACKS_NIX_GIT_NAME)" == "$tricky" ]]
}

test_env_override_not_persisted() {
  local repo="$1"
  load_config "$repo" install && save_config "$repo" || return 1
  local saved; saved="$(saved_value "$repo" JACKS_NIX_GIT_EMAIL)"
  # A one-off override for this run must not replace the saved value.
  export JACKS_NIX_GIT_EMAIL="someone.else@real-domain.dev"
  load_config "$repo" update && save_config "$repo" || return 1
  [[ "$(saved_value "$repo" JACKS_NIX_GIT_EMAIL)" == "$saved" ]]
}

test_reconfigure_persists() {
  local repo="$1"
  load_config "$repo" install && save_config "$repo" || return 1
  export JACKS_NIX_GIT_EMAIL="new.address@real-domain.dev"
  load_config "$repo" update || return 1
  # reconfigure prompts on /dev/tty, so simulate a confirmed value instead.
  _JN_LOAD_MODE=reconfigure
  save_config "$repo" || return 1
  [[ "$(saved_value "$repo" JACKS_NIX_GIT_EMAIL)" == "new.address@real-domain.dev" ]]
}

test_placeholder_email_not_saved() {
  local repo="$1"
  export JACKS_NIX_GIT_EMAIL='test$special@example.com'
  load_config "$repo" install
  if save_config "$repo"; then return 1; fi
  [[ ! -f "$repo/local/config.env" ]]
}

test_email_checks() {
  local bad good
  for bad in 'test$special@example.com' 'ci@EXAMPLE.org' 'a@build.test' 'a@foo.invalid' \
             'a@host.localhost' 'a@thing.example' 'no-at-sign' 'two@@at.com' 'sp ace@x.com' ''; do
    _git_email_problem "$bad" >/dev/null || { echo "accepted bad email: '$bad'"; return 1; }
  done
  for good in 'jackman3000@gmail.com' 'first.last+tag@sub.domain.co.uk' 'me@examples.com'; do
    if _git_email_problem "$good" >/dev/null; then echo "rejected good email: '$good'"; return 1; fi
  done
}

in_sandbox "special characters survive save/load"        test_roundtrip_special_chars
in_sandbox "environment override is not persisted"       test_env_override_not_persisted
in_sandbox "reconfigure persists the new value"          test_reconfigure_persists
in_sandbox "placeholder email is refused, nothing saved" test_placeholder_email_not_saved
in_sandbox "email validation"                            test_email_checks

real_after="$( [[ -f "$REAL_CONFIG" ]] && shasum "$REAL_CONFIG" || echo absent )"
if [[ "$real_before" == "$real_after" ]]; then
  pass "real local/config.env untouched"
else
  fail "real local/config.env was modified by the tests"
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All config tests passed."
else
  echo "$failures config test(s) failed."
  exit 1
fi
