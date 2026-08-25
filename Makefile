SHELL := /bin/sh

UNAME_S := $(shell uname -s)
BUILD_DIR := build
ROMS_DIR := roms
ROM_FILES := $(wildcard $(ROMS_DIR)/*)
CORE_SOURCES := \
	Sources/NeXTemuCore/NXTMemory.m \
	Sources/NeXTemuCore/NXTMC68040.m \
	Sources/NeXTemuCore/NXTMachine.m
APP_SOURCES := \
	Sources/NeXTemuApp/NXTAppDelegate.m \
	Sources/NeXTemuApp/main.m
TEST_SOURCE := Tests/NXTCoreTests.m

ifeq ($(UNAME_S),Darwin)
CC := clang
OBJCFLAGS := -std=c99 -Wall -Wextra -Werror -Wno-deprecated-declarations -Wno-objc-root-class -fno-objc-arc -fobjc-exceptions
GUI_LIBS := -framework Cocoa
FOUNDATION_LIBS := -framework Foundation
APP_EXECUTABLE := $(BUILD_DIR)/NeXTemu.app/Contents/MacOS/NeXTemu
else
GNUSTEP_CONFIG ?= gnustep-config
CC := clang
OBJCFLAGS := -std=c99 -Wall -Wextra -Werror -Wno-deprecated-declarations -fno-objc-arc $(shell $(GNUSTEP_CONFIG) --objc-flags)
GUI_LIBS := $(shell $(GNUSTEP_CONFIG) --gui-libs)
FOUNDATION_LIBS := $(shell $(GNUSTEP_CONFIG) --base-libs)
APP_EXECUTABLE := $(BUILD_DIR)/NeXTemu.app/NeXTemu
endif

CPPFLAGS := -ISources/NeXTemuCore -ISources/NeXTemuApp
OPTFLAGS ?= -O3

.PHONY: all clean test check-config

all: check-config $(APP_EXECUTABLE)

check-config:
ifeq ($(UNAME_S),Linux)
	@command -v $(GNUSTEP_CONFIG) >/dev/null 2>&1 || { echo "GNUstep development tools are required (gnustep-config not found)."; exit 1; }
endif

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

ifeq ($(UNAME_S),Darwin)
$(APP_EXECUTABLE): $(CORE_SOURCES) $(APP_SOURCES) Resources/Info.plist Resources/NeXTemu.icns $(ROM_FILES) | $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/NeXTemu.app/Contents/MacOS $(BUILD_DIR)/NeXTemu.app/Contents/Resources
	cp Resources/Info.plist $(BUILD_DIR)/NeXTemu.app/Contents/Info.plist
	cp Resources/NeXTemu.icns $(BUILD_DIR)/NeXTemu.app/Contents/Resources/NeXTemu.icns
	@if [ -d "$(ROMS_DIR)" ]; then \
		rm -rf $(BUILD_DIR)/NeXTemu.app/Contents/Resources/roms; \
		cp -R $(ROMS_DIR) $(BUILD_DIR)/NeXTemu.app/Contents/Resources/roms; \
	fi
	$(CC) $(CPPFLAGS) $(OBJCFLAGS) $(OPTFLAGS) $(CORE_SOURCES) $(APP_SOURCES) $(GUI_LIBS) -o $@
else
$(APP_EXECUTABLE): $(CORE_SOURCES) $(APP_SOURCES) Resources/Info.plist $(ROM_FILES) | $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/NeXTemu.app/Resources
	cp Resources/Info.plist $(BUILD_DIR)/NeXTemu.app/Resources/Info-gnustep.plist
	@if [ -d "$(ROMS_DIR)" ]; then \
		rm -rf $(BUILD_DIR)/NeXTemu.app/Resources/roms; \
		cp -R $(ROMS_DIR) $(BUILD_DIR)/NeXTemu.app/Resources/roms; \
	fi
	$(CC) $(CPPFLAGS) $(OBJCFLAGS) $(OPTFLAGS) $(CORE_SOURCES) $(APP_SOURCES) $(GUI_LIBS) -o $@
endif

$(BUILD_DIR)/core-tests: $(CORE_SOURCES) $(TEST_SOURCE) | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(OBJCFLAGS) $(OPTFLAGS) $(CORE_SOURCES) $(TEST_SOURCE) $(FOUNDATION_LIBS) -o $@

test: check-config $(BUILD_DIR)/core-tests
	./$(BUILD_DIR)/core-tests

clean:
	rm -rf $(BUILD_DIR)
