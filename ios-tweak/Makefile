TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouTubeAutoShorts

YouTubeAutoShorts_FILES = Tweak.x
YouTubeAutoShorts_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

