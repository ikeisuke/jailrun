PREFIX ?= $(HOME)/.local

.PHONY: install uninstall test

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
	install -m 644 lib/netns-const.sh $(PREFIX)/lib/jailrun/netns-const.sh
	install -m 644 lib/agent-wrapper.sh $(PREFIX)/lib/jailrun/agent-wrapper.sh
	install -m 644 lib/aws.sh $(PREFIX)/lib/jailrun/aws.sh
	$(foreach f,$(wildcard lib/platform/*.sh),install -m 644 $(f) $(PREFIX)/lib/jailrun/platform/$(notdir $(f));)
	install -m 755 lib/shims/codex $(PREFIX)/lib/jailrun/shims/codex
	install -m 755 lib/token.sh $(PREFIX)/lib/jailrun/token.sh
	install -m 755 lib/ruleset.sh $(PREFIX)/lib/jailrun/ruleset.sh
	install -m 644 lib/config-defaults.sh $(PREFIX)/lib/jailrun/config-defaults.sh
	install -m 755 lib/config-cmd.sh $(PREFIX)/lib/jailrun/config-cmd.sh
	install -m 644 lib/config.py $(PREFIX)/lib/jailrun/config.py
	install -m 644 lib/config_cli.py $(PREFIX)/lib/jailrun/config_cli.py
	install -m 644 lib/config_migrate.py $(PREFIX)/lib/jailrun/config_migrate.py
	install -m 644 lib/proxy.py $(PREFIX)/lib/jailrun/proxy.py
	install -m 644 lib/netns_const_loader.py $(PREFIX)/lib/jailrun/netns_const_loader.py

test:
	bats tests/
	python3 -m unittest discover -s tests -p 'test_*.py' -v

uninstall:
	rm -f $(PREFIX)/bin/jailrun
	rm -rf $(PREFIX)/lib/jailrun
