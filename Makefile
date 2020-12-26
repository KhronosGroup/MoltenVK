XC_PROJ := MoltenVKPackaging.xcodeproj
XC_SCHEME := MoltenVK Package

XCODEBUILD := set -o pipefail && $(shell command -v xcodebuild)
# Used to determine if xcpretty is available
XCPRETTY_PATH := $(shell command -v xcpretty 2> /dev/null)

OUTPUT_FMT_CMD =
ifdef XCPRETTY_PATH
	# Pipe output to xcpretty, while preserving full log as xcodebuild.log
	OUTPUT_FMT_CMD = | tee "xcodebuild.log" | xcpretty -c
else
	# Use xcodebuild -quiet parameter
	OUTPUT_FMT_CMD = -quiet
endif

# Specify individually (not as dependencies) so the sub-targets don't run in parallel
.PHONY: all
all:
	@$(MAKE) macos
	@$(MAKE) ios
	@$(MAKE) iossim
	@$(MAKE) maccat
	@$(MAKE) tvos
	@$(MAKE) tvossim

.PHONY: all-debug
all-debug:
	@$(MAKE) macos-debug
	@$(MAKE) ios-debug
	@$(MAKE) iossim-debug
	@$(MAKE) maccat-debug
	@$(MAKE) tvos-debug
	@$(MAKE) tvossim-debug

.PHONY: macos
macos:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (macOS only)" $(OUTPUT_FMT_CMD)

.PHONY: macos-debug
macos-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (macOS only)" -configuration "Debug" $(OUTPUT_FMT_CMD)

.PHONY: ios
ios:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" $(OUTPUT_FMT_CMD)

.PHONY: ios-debug
ios-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -configuration "Debug" $(OUTPUT_FMT_CMD)

.PHONY: iossim
iossim:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS Simulator" $(OUTPUT_FMT_CMD)

.PHONY: iossim-debug
iossim-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS Simulator" -configuration "Debug" $(OUTPUT_FMT_CMD)

.PHONY: maccat
maccat:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=macOS,variant=Mac Catalyst" $(OUTPUT_FMT_CMD)

.PHONY: maccat-debug
maccat-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=macOS,variant=Mac Catalyst" -configuration "Debug" $(OUTPUT_FMT_CMD)

.PHONY: tvos
tvos:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" $(OUTPUT_FMT_CMD)

.PHONY: tvos-debug
tvos-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -configuration "Debug" $(OUTPUT_FMT_CMD)

.PHONY: tvossim
tvossim:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS Simulator" $(OUTPUT_FMT_CMD)

.PHONY: tvossim-debug
tvossim-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS Simulator" -configuration "Debug" $(OUTPUT_FMT_CMD)

.PHONY: clean
clean:
	$(XCODEBUILD) clean -quiet -project "$(XC_PROJ)" -scheme "$(XC_SCHEME)"
	rm -rf Package

# Usually requires 'sudo make install'
.PHONY: install
install:
	rm -rf /Library/Frameworks/MoltenVK.framework
	rm -rf /Library/Frameworks/MoltenVK.xcframework
	cp -a Package/Latest/MoltenVK/MoltenVK.xcframework /Library/Frameworks/

# Deprecated target names
.PHONY: iosfat
iosfat:
	@$(MAKE) ios
	@$(MAKE) iossim

.PHONY: iosfat-debug
iosfat-debug:
	@$(MAKE) ios-debug
	@$(MAKE) iossim-debug

.PHONY: tvosfat
tvosfat:
	@$(MAKE) tvos
	@$(MAKE) tvossim

.PHONY: tvosfat-debug
tvosfat-debug:
	@$(MAKE) tvos-debug
	@$(MAKE) tvossim-debug
