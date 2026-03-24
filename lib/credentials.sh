#!/bin/sh
# credential extraction (AWS + GitHub)
# sourced by credential-guard.sh
#
# requires: $_WRAPPER_NAME, $DEFAULT_AWS_PROFILE, $ALLOWED_AWS_PROFILES,
#           $_DEFAULT_REGION, $GH_TOKEN_NAME, $JAILRUN_LIB
# exports: $_tmpdir, $_aws_config, $_aws_creds, $_gh_token, $_gh_token_source

_tmpdir=$(mktemp -d)
trap 'rm -rf "$_tmpdir"' EXIT

# --- AWS credentials ---
. "$JAILRUN_LIB/aws.sh"
_setup_aws_credentials || true

# --- GitHub token ---
case "$(uname)" in
  Darwin) . "$JAILRUN_LIB/platform/keychain-darwin.sh" ;;
  Linux)  . "$JAILRUN_LIB/platform/keychain-linux.sh" ;;
esac
_get_gh_token

if [ -n "$_gh_token" ]; then
  echo "[$_WRAPPER_NAME] GitHub: PAT ($_gh_token_source)" >&2
else
  echo "[$_WRAPPER_NAME] WARN: GitHub PAT not configured (see docs/github-pat-setup.md)" >&2
fi
