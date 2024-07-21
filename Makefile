ARCHS := arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES := TrollFools

include $(THEOS)/makefiles/common.mk

XCODEPROJ_NAME += TrollFools

include $(THEOS_MAKE_PATH)/xcodeproj.mk

# SUBPROJECTS += TrollFoolsTweak

include $(THEOS_MAKE_PATH)/aggregate.mk

before-all::
	devkit/standardize-entitlements.sh

before-package::
	$(ECHO_NOTHING)ldid -STrollFools/TrollFools.entitlements $(THEOS_STAGING_DIR)/Applications/TrollFools.app$(ECHO_END)

export THEOS_PACKAGE_INSTALL_PREFIX
export THEOS_STAGING_DIR
after-package::
	devkit/tipa.sh