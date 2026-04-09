INSTALL_DIR ?= /usr/local/bin
TARGET      := $(INSTALL_DIR)/tempo

.PHONY: install uninstall

install:
	cp tempo.sh $(TARGET)
	chmod +x $(TARGET)
	@echo "Installed: $(TARGET)"

uninstall:
	rm -f $(TARGET)
	@echo "Removed: $(TARGET)"
