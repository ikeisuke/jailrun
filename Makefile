PREFIX ?= $(HOME)/.local

.PHONY: install uninstall

install:
	install -d $(PREFIX)/bin
	install -d $(PREFIX)/lib/jailrun
	install -m 755 bin/jailrun $(PREFIX)/bin/jailrun
	install -m 644 lib/credential-guard.sh $(PREFIX)/lib/jailrun/credential-guard.sh
	install -m 644 lib/agent-wrapper.sh $(PREFIX)/lib/jailrun/agent-wrapper.sh
	install -m 755 lib/token.sh $(PREFIX)/lib/jailrun/token.sh

uninstall:
	rm -f $(PREFIX)/bin/jailrun
	rm -rf $(PREFIX)/lib/jailrun
