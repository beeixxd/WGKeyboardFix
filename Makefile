TARGET := iphone:clang:latest:13.0
ARCHS = arm64

THEOS_DEVICE_C_FLAGS = -fobjc-arc

include $(THEOS)/makefiles/common.mk

# 用 LIBRARY 而不是 TWEAK:
# 这个 dylib 是要被直接 insert_dylib 进 Whitegram 这一个 IPA 里用的
# (跟包里已有的 sideloadFixerLol.dylib / SideloadFix27.dylib 同款做法)，
# 不是要靠 CydiaSubstrate/ElleKit 按 bundle id 全局注入的系统 tweak，
# 所以不需要 Tweak.plist Filter，也不需要链接任何 hook 库。
LIBRARY_NAME = WGKeyboardFix

WGKeyboardFix_FILES = WGKeyboardFix.m
WGKeyboardFix_FRAMEWORKS = UIKit Foundation
WGKeyboardFix_CFLAGS = -fobjc-arc -Wall

include $(THEOS_MAKE_PATH)/library.mk

# 如果你更喜欢用 Logos 语法版本 (Tweak.xm), 把上面的
# WGKeyboardFix_FILES 换成 Tweak.xm 再 make 一次即可，
# 两个文件实现的是完全一样的逻辑，二选一编译就行，不要同时编译两个
# (会重复定义 hook, 虽然理论上不会崩溃但没必要)。
