ARCHS = armv7 arm64 arm64e
CFLAGS = -miphoneos-version-min=9.0 -F $(THEOS)/frameworks
LDFLAGS = -miphoneos-version-min=9.0 -F $(THEOS)/frameworks -framework Preferences

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = VoltagePreferences
VoltagePreferences_FILES = VoltagePreferences.mm
VoltagePreferences_INSTALL_PATH = /Library/PreferenceBundles
VoltagePreferences_FRAMEWORKS = UIKit
VoltagePreferences_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/VoltagePreferences.plist$(ECHO_END)
