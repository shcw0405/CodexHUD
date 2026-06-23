SWIFTC ?= /usr/bin/swiftc
BUILD_DIR := .build
CORE_SOURCES := $(wildcard Sources/CodexHUDCore/*.swift)
APP_SOURCES := $(wildcard Sources/CodexHUD/*.swift)
DIRECT_TEST_SOURCES := $(wildcard Tests/DirectTests/*.swift)

.PHONY: test binary build run clean probe

test:
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) -parse-as-library $(CORE_SOURCES) $(DIRECT_TEST_SOURCES) -o $(BUILD_DIR)/codexhud-core-tests
	$(BUILD_DIR)/codexhud-core-tests

binary:
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) -emit-library -emit-module -module-name CodexHUDCore $(CORE_SOURCES) \
		-emit-module-path $(BUILD_DIR)/CodexHUDCore.swiftmodule \
		-Xlinker -install_name -Xlinker @rpath/libCodexHUDCore.dylib \
		-o $(BUILD_DIR)/libCodexHUDCore.dylib
	$(SWIFTC) $(APP_SOURCES) -I $(BUILD_DIR) -L $(BUILD_DIR) -lCodexHUDCore \
		-Xlinker -rpath -Xlinker @executable_path \
		-framework AppKit -o $(BUILD_DIR)/CodexHUD

build: binary
	rm -rf $(BUILD_DIR)/CodexHUD.app
	mkdir -p $(BUILD_DIR)/CodexHUD.app/Contents/MacOS
	mkdir -p $(BUILD_DIR)/CodexHUD.app/Contents/Resources
	cp $(BUILD_DIR)/CodexHUD $(BUILD_DIR)/CodexHUD.app/Contents/MacOS/CodexHUD
	cp $(BUILD_DIR)/libCodexHUDCore.dylib $(BUILD_DIR)/CodexHUD.app/Contents/MacOS/libCodexHUDCore.dylib
	cp Resources/Info.plist $(BUILD_DIR)/CodexHUD.app/Contents/Info.plist

run: build
	open -n $(BUILD_DIR)/CodexHUD.app

probe:
	python3 Scripts/probe-codex-rpc.py

clean:
	rm -rf $(BUILD_DIR)
