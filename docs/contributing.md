# Contributing

## Development Environment

### Prerequisites

- macOS or Linux (WSL2 supported)
- [bats](https://github.com/bats-core/bats-core) — Bash test framework
- Python 3.x — For proxy and config modules
- Git

### Setup

```bash
git clone <repo-url>
cd jailrun
make test    # verify everything passes
```

No build step is required — jailrun is a collection of shell scripts and Python modules.

## Running Tests

```bash
# run all tests (bats + Python unittest)
make test

# run only bats tests
bats tests/

# run a specific bats test file
bats tests/sandbox_linux_systemd.bats

# run only Python tests
python3 -m unittest discover -s tests -p 'test_*.py' -v

# run a specific Python test file
python3 -m unittest tests/test_proxy.py -v
```

### Test Structure

```
tests/
├── helpers.bash               Common test helpers
├── jailrun.bats               CLI entrypoint tests
├── codex_args.bats            Codex argument rewriting tests
├── config.bats                Config loading/migration tests
├── config_cmd.bats            Config CLI subcommand tests
├── sandbox_linux_systemd.bats systemd property generation tests
├── credential_guard.bats      Double-sandbox prevention tests
├── sandbox_profile.bats       Seatbelt profile generation tests
├── passthrough_env.bats       Environment variable passthrough tests
├── lint.bats                  Shell script linting checks
└── test_proxy.py              Proxy unit tests (Python unittest)
```

### Writing Tests

**Shell tests (bats)**:
- Use `load helpers` and `setup_jailrun_env` for environment setup
- Use `run` to capture exit status and output
- Assert with `[ "$status" -eq 0 ]` and `[[ "$output" == *"pattern"* ]]`
- Create temp directories with `mktemp -d` and clean up in `teardown()`

**Python tests (unittest)**:
- Place in `tests/test_*.py` (auto-discovered by `make test`)
- Use `unittest.mock.patch` for mocking — avoid real network connections
- Import from `lib/` using `sys.path.insert`

## Coding Conventions

### Shell Scripts

- **Shebang**: `#!/bin/sh` (POSIX sh, not bash/zsh)
- **Strict mode**: `set -eu` for scripts that are executed (not sourced)
- **Variable prefix**: `_` for local/internal variables (e.g., `_tmpdir`, `_service`)
- **Function prefix**: `_` for internal functions (e.g., `_build_env_spec`)
- **No bashisms**: Avoid `[[ ]]`, arrays, `local -a`, etc. Use `case` instead of `[[ ]]` for pattern matching
- **No Japanese in scripts**: Keep all script content in English (enforced by lint.bats)

### Python

- **Shebang**: `#!/usr/bin/env python3`
- **Imports**: Standard library only (no pip dependencies)
- **Type hints**: Use `from __future__ import annotations` for forward references

### File Organization

- `lib/` — Core library (sourced or imported)
- `lib/platform/` — OS-specific implementations
- `bin/` — Entrypoints
- `tests/` — All tests
- `docs/` — Documentation

## Making Changes

1. Create a branch from `main`
2. Make changes
3. Run `make test` to verify all tests pass
4. Commit with a descriptive message

### Adding a New Agent

To add support for a new AI coding agent:

1. Add the agent name to the `case` statement in `bin/jailrun`
2. If the agent needs arg rewriting (like Codex), add a handler in `agent-wrapper.sh`
3. Add write-allow paths for the agent's data directories in `sandbox.sh`
4. Update `README.md` with usage examples

### Adding a New Platform

1. Create `lib/platform/sandbox-<platform>.sh`
2. Implement `_setup_sandbox()` and `_build_sandbox_exec()`
3. Add a `case` branch in `sandbox.sh`
4. Add tests in `tests/`
