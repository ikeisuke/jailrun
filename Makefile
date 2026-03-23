PREFIX ?= $(HOME)/.local

.PHONY: install uninstall

install:
	install -d $(PREFIX)/bin
	install -d $(PREFIX)/lib/jailrun
	install -d $(PREFIX)/lib/jailrun/shims
	install -d $(PREFIX)/lib/jailrun/platform
	install -m 755 bin/jailrun $(PREFIX)/bin/jailrun
	install -m 644 lib/credential-guard.sh $(PREFIX)/lib/jailrun/credential-guard.sh
	install -m 644 lib/config.sh $(PREFIX)/lib/jailrun/config.sh
	install -m 644 lib/credentials.sh $(PREFIX)/lib/jailrun/credentials.sh
	install -m 644 lib/sandbox.sh $(PREFIX)/lib/jailrun/sandbox.sh
	install -m 644 lib/agent-wrapper.sh $(PREFIX)/lib/jailrun/agent-wrapper.sh
	install -m 644 lib/aws.sh $(PREFIX)/lib/jailrun/aws.sh
	install -m 644 lib/platform/keychain-darwin.sh $(PREFIX)/lib/jailrun/platform/keychain-darwin.sh
	install -m 644 lib/platform/keychain-linux.sh $(PREFIX)/lib/jailrun/platform/keychain-linux.sh
	install -m 644 lib/platform/git-worktree.sh $(PREFIX)/lib/jailrun/platform/git-worktree.sh
	install -m 644 lib/platform/sandbox-darwin.sh $(PREFIX)/lib/jailrun/platform/sandbox-darwin.sh
	install -m 644 lib/platform/sandbox-linux.sh $(PREFIX)/lib/jailrun/platform/sandbox-linux.sh
	install -m 755 lib/shims/codex $(PREFIX)/lib/jailrun/shims/codex
	install -m 755 lib/token.sh $(PREFIX)/lib/jailrun/token.sh

uninstall:
	rm -f $(PREFIX)/bin/jailrun
	rm -rf $(PREFIX)/lib/jailrun
