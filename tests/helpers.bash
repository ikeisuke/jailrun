# Common test helpers

# Set up JAILRUN_DIR and JAILRUN_LIB pointing to repo's lib/
setup_jailrun_env() {
  export JAILRUN_DIR="$BATS_TEST_DIRNAME/../bin"
  export JAILRUN_LIB="$BATS_TEST_DIRNAME/../lib"
  export WRAPPER_NAME="claude"
}
