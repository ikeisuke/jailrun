#!/usr/bin/env bats
# Unit 003: tests/aws.bats — lib/aws.sh bats tests
#
# Spec: .aidlc/cycles/v0.3.1/plans/unit-003-plan.md
# Design: .aidlc/cycles/v0.3.1/design-artifacts/logical-designs/
#         unit_003_aws_bats_tests_logical_design.md
#
# Covers _setup_aws_credentials and _write_aws_profile with aws PATH shim.
# Real aws CLI and AWS STS are never reached (PATH fixed to shim-bin:sysbin).

load helpers

_aws_preflight() {
  setup_jailrun_env
  export _WRAPPER_NAME=jailrun
  export _DEFAULT_REGION=us-east-1
  export DEFAULT_AWS_PROFILE=default
  export ALLOWED_AWS_PROFILES=""
  unset AGENT_AWS_PROFILES
  unset MOCK_AWS_EXPORT_STATE_DEFAULT MOCK_AWS_EXPORT_JSON_DEFAULT MOCK_AWS_REGION_DEFAULT
  unset MOCK_AWS_EXPORT_STATE_WORK MOCK_AWS_EXPORT_JSON_WORK MOCK_AWS_REGION_WORK
  unset MOCK_AWS_EXPORT_STATE_PROD MOCK_AWS_EXPORT_JSON_PROD MOCK_AWS_REGION_PROD
}

_aws_source() {
  # shellcheck disable=SC1091
  . "$JAILRUN_LIB/aws.sh"
}

_JSON_OK_DEFAULT='{"AccessKeyId":"AKIATESTKEY","SecretAccessKey":"secrettestvalue","SessionToken":"sessiontokentest","Expiration":"2026-01-01T00:00:00Z"}'
_JSON_NO_TOKEN='{"AccessKeyId":"AKIATESTKEY","SecretAccessKey":"secrettestvalue","SessionToken":"","Expiration":"2026-01-01T00:00:00Z"}'
_JSON_WORK='{"AccessKeyId":"WORKKEY","SecretAccessKey":"WORKSECRET","SessionToken":"WORKTOKEN","Expiration":"2026-01-01T00:00:00Z"}'
_JSON_DEFAULT_AK1='{"AccessKeyId":"AK1","SecretAccessKey":"SK1","SessionToken":"ST1","Expiration":"2026-01-01T00:00:00Z"}'
_JSON_WORK_AK2='{"AccessKeyId":"AK2","SecretAccessKey":"SK2","SessionToken":"ST2","Expiration":"2026-01-01T00:00:00Z"}'
_JSON_PROD_AK3='{"AccessKeyId":"AK3","SecretAccessKey":"SK3","SessionToken":"ST3","Expiration":"2026-01-01T00:00:00Z"}'

@test "AW1 single default profile success (session_token present, jq optional)" {
  _aws_preflight
  setup_aws_shims

  export MOCK_AWS_EXPORT_STATE_DEFAULT=ok
  export MOCK_AWS_EXPORT_JSON_DEFAULT="$_JSON_OK_DEFAULT"
  export MOCK_AWS_REGION_DEFAULT=us-east-1

  _aws_source
  run _setup_aws_credentials

  [ "$status" -eq 0 ]
  [[ "$output" == *"AWS: default (temporary credentials)"* ]]

  assert_aws_configure_called export-credentials default
  assert_aws_configure_called get-region default

  assert_aws_config_section_count default 1
  assert_aws_config_section_count "profile default" 1
  assert_aws_config_section_order default "profile default"
  assert_aws_config_line default region us-east-1
  assert_aws_config_line "profile default" region us-east-1

  assert_aws_creds_section_count default 2
  assert_aws_creds_section_order default default
  assert_aws_creds_line_in_nth default 1 aws_access_key_id AKIATESTKEY
  assert_aws_creds_line_in_nth default 1 aws_secret_access_key secrettestvalue
  assert_aws_creds_line_in_nth default 1 aws_session_token sessiontokentest
  assert_aws_creds_line_in_nth default 2 aws_access_key_id AKIATESTKEY
  assert_aws_creds_line_in_nth default 2 aws_secret_access_key secrettestvalue
  assert_aws_creds_line_in_nth default 2 aws_session_token sessiontokentest
}

@test "AW2 no session_token (aws_session_token line omitted)" {
  _aws_preflight
  setup_aws_shims

  export MOCK_AWS_EXPORT_STATE_DEFAULT=ok
  export MOCK_AWS_EXPORT_JSON_DEFAULT="$_JSON_NO_TOKEN"
  export MOCK_AWS_REGION_DEFAULT=us-east-1

  _aws_source
  run _setup_aws_credentials

  [ "$status" -eq 0 ]
  assert_aws_creds_section default
  assert_aws_creds_line default aws_access_key_id AKIATESTKEY
  assert_aws_creds_line default aws_secret_access_key secrettestvalue
  assert_aws_creds_line_absent default aws_session_token
}

@test "AW3 AGENT_AWS_PROFILES override (default section override credentials)" {
  _aws_preflight
  setup_aws_shims

  export AGENT_AWS_PROFILES=work
  export MOCK_AWS_EXPORT_STATE_WORK=ok
  export MOCK_AWS_EXPORT_JSON_WORK="$_JSON_WORK"
  export MOCK_AWS_REGION_WORK=ap-northeast-1

  _aws_source
  run _setup_aws_credentials

  [ "$status" -eq 0 ]
  assert_aws_configure_called export-credentials work
  assert_aws_configure_not_called export-credentials default

  # config: [default] once, [profile work] once, no [profile default]
  assert_aws_config_section_count default 1
  assert_aws_config_section_count "profile work" 1
  assert_aws_config_section_not_exists "profile default"
  assert_aws_config_section_order default "profile work"
  assert_aws_config_line default region ap-northeast-1
  assert_aws_config_line "profile work" region ap-northeast-1

  # creds: [default] once (work credentials), [work] once
  assert_aws_creds_section_count default 1
  assert_aws_creds_section_count work 1
  assert_aws_creds_section_order default work
  assert_aws_creds_line default aws_access_key_id WORKKEY
  assert_aws_creds_line default aws_secret_access_key WORKSECRET
  assert_aws_creds_line default aws_session_token WORKTOKEN
  assert_aws_creds_line work aws_access_key_id WORKKEY
  assert_aws_creds_line work aws_secret_access_key WORKSECRET
}

@test "AW4 multiple profiles (default + work, write order and default dedup)" {
  _aws_preflight
  setup_aws_shims

  export AGENT_AWS_PROFILES="default work"
  export MOCK_AWS_EXPORT_STATE_DEFAULT=ok
  export MOCK_AWS_EXPORT_JSON_DEFAULT="$_JSON_DEFAULT_AK1"
  export MOCK_AWS_REGION_DEFAULT=us-east-1
  export MOCK_AWS_EXPORT_STATE_WORK=ok
  export MOCK_AWS_EXPORT_JSON_WORK="$_JSON_WORK_AK2"
  export MOCK_AWS_REGION_WORK=ap-northeast-1

  _aws_source
  run _setup_aws_credentials

  [ "$status" -eq 0 ]
  assert_aws_configure_called export-credentials default
  assert_aws_configure_called export-credentials work

  assert_aws_config_section_count default 1
  assert_aws_config_section_count "profile default" 1
  assert_aws_config_section_count "profile work" 1
  assert_aws_config_section_order default "profile default" "profile work"
  assert_aws_config_line default region us-east-1
  assert_aws_config_line "profile default" region us-east-1
  assert_aws_config_line "profile work" region ap-northeast-1

  assert_aws_creds_section_count default 2
  assert_aws_creds_section_count work 1
  assert_aws_creds_section_order default default work
  assert_aws_creds_line_in_nth default 1 aws_access_key_id AK1
  assert_aws_creds_line_in_nth default 1 aws_secret_access_key SK1
  assert_aws_creds_line_in_nth default 2 aws_access_key_id AK1
  assert_aws_creds_line_in_nth default 2 aws_secret_access_key SK1
  assert_aws_creds_line work aws_access_key_id AK2
  assert_aws_creds_line work aws_secret_access_key SK2
}

@test "AW5 allow list filter (prod excluded, work only)" {
  _aws_preflight
  setup_aws_shims

  export ALLOWED_AWS_PROFILES=work
  export AGENT_AWS_PROFILES="work prod"
  export MOCK_AWS_EXPORT_STATE_WORK=ok
  export MOCK_AWS_EXPORT_JSON_WORK="$_JSON_WORK_AK2"
  export MOCK_AWS_REGION_WORK=ap-northeast-1
  export MOCK_AWS_EXPORT_STATE_PROD=ok
  export MOCK_AWS_EXPORT_JSON_PROD="$_JSON_PROD_AK3"
  export MOCK_AWS_REGION_PROD=us-west-2

  _aws_source
  run _setup_aws_credentials

  [ "$status" -eq 0 ]
  [[ "$output" == *"AWS profile 'prod' is not in the allow list"* ]]

  assert_aws_configure_called export-credentials work
  assert_aws_configure_not_called export-credentials prod

  assert_aws_creds_section work
  assert_aws_creds_section_not_exists prod
  assert_aws_config_section_not_exists "profile prod"
}

@test "AW6 abnormal aws configure export-credentials failure (fail-open: WARN + section not written)" {
  _aws_preflight
  setup_aws_shims

  export AGENT_AWS_PROFILES=default
  export MOCK_AWS_EXPORT_STATE_DEFAULT=fail

  _aws_source
  run _setup_aws_credentials

  [ "$status" -eq 0 ]
  [[ "$output" == *"failed to retrieve credentials for AWS profile 'default' (need aws sso login?)"* ]]

  assert_aws_configure_called export-credentials default
  assert_aws_configure_not_called get-region default

  assert_aws_config_section_not_exists default
  assert_aws_config_section_not_exists "profile default"
  assert_aws_creds_section_not_exists default
}

@test "AW7 aws not installed (shim removed, function exits with empty file)" {
  _aws_preflight
  setup_aws_shims

  rm -f "$BATS_TEST_TMPDIR/shim-bin/aws"

  _aws_source
  run _setup_aws_credentials

  [ "$status" -eq 0 ]

  # Both files exist (touched in aws.sh head) but have zero section lines
  [ -f "$_aws_config" ]
  [ -f "$_aws_creds" ]
  _config_sections=$(grep -c '^\[' "$_aws_config" || true)
  _creds_sections=$(grep -c '^\[' "$_aws_creds" || true)
  [ "$_config_sections" = "0" ]
  [ "$_creds_sections" = "0" ]

  assert_aws_configure_not_called export-credentials default
}

@test "AW8 _write_aws_profile unit (session_token empty omitted)" {
  _aws_preflight
  setup_aws_shims

  _aws_source

  _write_aws_profile "myprof" "myprof" "AK" "SK" "" "ap-northeast-1"

  assert_aws_config_section myprof
  assert_aws_config_line myprof region ap-northeast-1
  assert_aws_creds_section myprof
  assert_aws_creds_line myprof aws_access_key_id AK
  assert_aws_creds_line myprof aws_secret_access_key SK
  assert_aws_creds_line_absent myprof aws_session_token
}

@test "AW9 jq absent (grep/cut fallback, same as AW1)" {
  _aws_preflight
  setup_aws_shims_without_jq

  export MOCK_AWS_EXPORT_STATE_DEFAULT=ok
  export MOCK_AWS_EXPORT_JSON_DEFAULT="$_JSON_OK_DEFAULT"
  export MOCK_AWS_REGION_DEFAULT=us-east-1

  _aws_source
  run _setup_aws_credentials

  [ "$status" -eq 0 ]
  [[ "$output" == *"AWS: default (temporary credentials)"* ]]

  assert_aws_configure_called export-credentials default
  assert_aws_configure_called get-region default

  assert_aws_config_section_count default 1
  assert_aws_config_section_count "profile default" 1
  assert_aws_config_section_order default "profile default"
  assert_aws_config_line default region us-east-1
  assert_aws_config_line "profile default" region us-east-1

  assert_aws_creds_section_count default 2
  assert_aws_creds_section_order default default
  assert_aws_creds_line_in_nth default 1 aws_access_key_id AKIATESTKEY
  assert_aws_creds_line_in_nth default 1 aws_secret_access_key secrettestvalue
  assert_aws_creds_line_in_nth default 1 aws_session_token sessiontokentest
  assert_aws_creds_line_in_nth default 2 aws_access_key_id AKIATESTKEY
  assert_aws_creds_line_in_nth default 2 aws_secret_access_key secrettestvalue
  assert_aws_creds_line_in_nth default 2 aws_session_token sessiontokentest
}
