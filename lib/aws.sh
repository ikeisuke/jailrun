#!/bin/sh
# AWS credential isolation
# Sourced by credential-guard.sh
#
# Requires: $_tmpdir, $_WRAPPER_NAME, $DEFAULT_AWS_PROFILE,
#           $ALLOWED_AWS_PROFILES, $_DEFAULT_REGION to be set
#
# Outputs: $_aws_config, $_aws_creds (paths to temporary files)

_aws_config="$_tmpdir/aws-config"
_aws_creds="$_tmpdir/aws-credentials"
touch "$_aws_config" "$_aws_creds"

_write_aws_profile() {
  local _section_config="$1" _section_creds="$2" _ak="$3" _sk="$4" _st="$5" _region="$6"
  echo "[$_section_config]" >> "$_aws_config"
  echo "region = $_region" >> "$_aws_config"
  echo "" >> "$_aws_config"
  echo "[$_section_creds]" >> "$_aws_creds"
  echo "aws_access_key_id = $_ak" >> "$_aws_creds"
  echo "aws_secret_access_key = $_sk" >> "$_aws_creds"
  [ -n "$_st" ] && echo "aws_session_token = $_st" >> "$_aws_creds"
  echo "" >> "$_aws_creds"
}

_setup_aws_credentials() {
  local _load_profiles="${AGENT_AWS_PROFILES:-$DEFAULT_AWS_PROFILE}"

  # Reject profiles not in the allow list
  if [ -n "$_load_profiles" ] && [ -n "$ALLOWED_AWS_PROFILES" ]; then
    local _filtered_profiles=""
    for _p in $_load_profiles; do
      case " $ALLOWED_AWS_PROFILES " in
        *" $_p "*)
          _filtered_profiles="${_filtered_profiles:+$_filtered_profiles }$_p"
          ;;
        *)
          echo "[$_WRAPPER_NAME] WARN: AWS profile '$_p' is not in the allow list (ALLOWED_AWS_PROFILES)" >&2
          ;;
      esac
    done
    _load_profiles="$_filtered_profiles"
  fi

  # When AGENT_AWS_PROFILES overrides, align DEFAULT_AWS_PROFILE to first loaded profile
  if [ -n "${AGENT_AWS_PROFILES:-}" ] && [ -n "$_load_profiles" ]; then
    for _p in $_load_profiles; do
      DEFAULT_AWS_PROFILE="$_p"
      break
    done
  fi

  local _default_written=false
  local _default_ak="" _default_sk="" _default_st="" _default_region=""

  if command -v aws >/dev/null 2>&1 && [ -n "$_load_profiles" ]; then
    for _profile in $_load_profiles; do
      local _exported _ak _sk _st _region
      if _exported=$(aws configure export-credentials --profile "$_profile" --format process 2>/dev/null); then
        if command -v jq >/dev/null 2>&1; then
          _ak=$(echo "$_exported" | jq -r .AccessKeyId)
          _sk=$(echo "$_exported" | jq -r .SecretAccessKey)
          _st=$(echo "$_exported" | jq -r '.SessionToken // empty')
        else
          _ak=$(echo "$_exported" | grep -o '"AccessKeyId"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 || true)
          _sk=$(echo "$_exported" | grep -o '"SecretAccessKey"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 || true)
          _st=$(echo "$_exported" | grep -o '"SessionToken"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 || true)
        fi

        _region=$(aws configure get region --profile "$_profile" 2>/dev/null || echo "$_DEFAULT_REGION")

        if [ "$_default_written" = false ] && [ "$_profile" = "$DEFAULT_AWS_PROFILE" ]; then
          _write_aws_profile "default" "default" "$_ak" "$_sk" "$_st" "$_region"
          _default_written=true
        fi

        if [ "$_profile" = "$DEFAULT_AWS_PROFILE" ]; then
          _default_ak="$_ak" _default_sk="$_sk" _default_st="$_st" _default_region="$_region"
        fi

        _write_aws_profile "profile $_profile" "$_profile" "$_ak" "$_sk" "$_st" "$_region"
        echo "[$_WRAPPER_NAME] AWS: $_profile (temporary credentials)" >&2
      else
        echo "[$_WRAPPER_NAME] WARN: failed to retrieve credentials for AWS profile '$_profile' (need aws sso login?)" >&2
      fi
    done

    if [ "$_default_written" = false ] && [ -n "$_default_ak" ]; then
      _write_aws_profile "default" "default" "$_default_ak" "$_default_sk" "${_default_st:-}" "${_default_region:-$_DEFAULT_REGION}"
    fi
  fi
}
