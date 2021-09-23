#TARGET = simulator:clang::7.0
#ARCHS = x86_64
ARCHS = arm64e arm64 armv7
CFLAGS = -miphoneos-version-min=9.0 -Wno-objc-method-access -Wno-error -Wno-objc-multiple-method-names
LDFLAGS = -miphoneos-version-min=9.0 -framework UIKit -sectcreate __TEXT __cbuild cbuild.txt -Wno-error

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VoltageHooks
VoltageHooks_FILES = VoltageHooks.x VoltageSuppressionSession.m

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"

SUBPROJECTS += ../VoltagePreferences
include $(THEOS_MAKE_PATH)/aggregate.mk
