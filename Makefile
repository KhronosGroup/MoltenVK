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

# Collect all build settings defined on the command-line (eg: MVK_HIDE_VULKAN_SYMBOLS=1, MVK_CONFIG_LOG_LEVEL=3...)
MAKEARGS := $(strip \
  $(foreach v,$(.VARIABLES),\
    $(if $(filter command\ line,$(origin $(v))),\
      $(v)=$(value $(v)) ,)))

# Specify individually (not as dependencies) so the sub-targets don't run in parallel
# visionos and visionossim are currently excluded from `all` because they require
# Xcode 15+ and will abort a multi-platform build on earlier Xcode versions.
.PHONY: all
all:
	@$(MAKE) macos
	@$(MAKE) ios
	@$(MAKE) iossim
	@$(MAKE) maccat
	@$(MAKE) tvos
	@$(MAKE) tvossim
#	@$(MAKE) visionos       # Requires Xcode 15+
#	@$(MAKE) visionossim    # Requires Xcode 15+

.PHONY: all-debug
all-debug:
	@$(MAKE) macos-debug
	@$(MAKE) ios-debug
	@$(MAKE) iossim-debug
	@$(MAKE) maccat-debug
	@$(MAKE) tvos-debug
	@$(MAKE) tvossim-debug
#	@$(MAKE) visionos-debug       # Requires Xcode 15+
#	@$(MAKE) visionossim-debug    # Requires Xcode 15+

.PHONY: macos
macos:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (macOS only)" -destination "generic/platform=macOS" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: macos-debug
macos-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (macOS only)" -destination "generic/platform=macOS" -configuration "Debug" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: ios
ios:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: ios-debug
ios-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS" -configuration "Debug" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: iossim
iossim:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS Simulator" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: iossim-debug
iossim-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (iOS only)" -destination "generic/platform=iOS Simulator" -configuration "Debug" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: maccat
maccat:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (MacCat only)" -destination "generic/platform=macOS,variant=Mac Catalyst" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: maccat-debug
maccat-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (MacCat only)" -destination "generic/platform=macOS,variant=Mac Catalyst" -configuration "Debug" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: tvos
tvos:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: tvos-debug
tvos-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS" -configuration "Debug" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: tvossim
tvossim:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS Simulator" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: tvossim-debug
tvossim-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (tvOS only)" -destination "generic/platform=tvOS Simulator" -configuration "Debug" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: visionos
visionos:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (visionOS only)" -destination "generic/platform=xrOS" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: visionos-debug
visionos-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (visionOS only)" -destination "generic/platform=xrOS" -configuration "Debug" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: visionossim
visionossim:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (visionOS only)" -destination "generic/platform=xrOS Simulator" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: visionossim-debug
visionossim-debug:
	$(XCODEBUILD) build -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (visionOS only)" -destination "generic/platform=xrOS Simulator" -configuration "Debug" GCC_PREPROCESSOR_DEFINITIONS='$${inherited} $(MAKEARGS)' $(OUTPUT_FMT_CMD)

.PHONY: clean
clean:
	$(XCODEBUILD) clean -project "$(XC_PROJ)" -scheme "$(XC_SCHEME) (macOS only)" -destination "generic/platform=macOS" $(OUTPUT_FMT_CMD)
	rm -rf Package

# Usually requires 'sudo make install'
.PHONY: install
install:
	$ rm -f /usr/local/lib/libMoltenVK.dylib
	$ cp -p Package/Latest/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib /usr/local/lib
