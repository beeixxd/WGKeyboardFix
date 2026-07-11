//
//  WGKeyboardFix.m
//
//  纯 Objective-C 版本，不依赖 Logos / libsubstrate / libhooker，
//  只用 <objc/runtime.h> 做 method swizzling。
//  和包里已有的 sideloadFixerLol.dylib / SideloadFix27.dylib 是同一种
//  "直接注入进单个 IPA、无需越狱" 的风格 (没有任何外部 hook 库依赖)。
//
//  用法: 作为一个独立 dylib 编译出来，放进
//  Payload/Telegram.app/WGKeyboardFix.dylib，
//  然后在主程序 Telegram 的 Mach-O 里加一条:
//      LC_LOAD_WEAK_DYLIB  @executable_path/WGKeyboardFix.dylib
//  (跟包里已有的那 5 个 sideload dylib 完全一样的做法，
//   可以用 insert_dylib / optool / TrollFools 来加这条 load command)
//
//  编译 (在装有 Xcode 的 macOS 上):
//    clang -dynamiclib -arch arm64 -miphoneos-version-min=13.0 \
//      -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//      -framework UIKit -framework Foundation \
//      -o WGKeyboardFix.dylib WGKeyboardFix.m
//    ldid -S WGKeyboardFix.dylib   # 或用你签IPA时的证书重新签名这个dylib
//
//  也可以直接把这个文件放进现有 Theos 工程当 LIBRARY 目标编译，
//  见随附的 Makefile。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gWGPasscodeRecentlyShown = NO;

#pragma mark - 强制交还第一响应者

static void WGForceResignKeyboard(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 经典技巧: 让 UIKit 自己去找当前真正的第一响应者并 resign，
        // 不需要我们知道它具体挂在哪个 window / 哪个控件上。
        // 这一步是解决"密码框已经不在可见层级、但仍是第一响应者"这种
        // 孤立态的关键，比直接操作 keyWindow 更可靠。
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder)
                                                    to:nil
                                                  from:nil
                                              forEvent:nil];

        // 双保险: 对当前 active 场景的 key window 再调用一次 endEditing。
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) { keyWindow = w; break; }
                    }
                }
                if (keyWindow) break;
            }
        }
        if (!keyWindow) {
            keyWindow = [UIApplication sharedApplication].keyWindow;
        }
        [keyWindow endEditing:YES];
    });
}

#pragma mark - Hook 1: PasscodeEntryController 生命周期

// 私有 Swift 类，ObjC 可见名是 _TtC10PasscodeUI23PasscodeEntryController
// (对应 Swift: PasscodeUI.PasscodeEntryController)
// 通过静态分析确认: 该类内部的输入框节点 (PasscodeInputFieldNode) 只导出了
// activate()，找不到任何 deactivate / resign 相关的导出符号，
// EntryController 自己也没有重写 viewDidDisappear:。
// 所以选 -dealloc 作为 hook 点: Swift NSObject 子类的 deinit 保证会走到
// ObjC 的 dealloc selector，是最稳定、跨版本兼容性最好的收尾时机。

static IMP gOrigPasscodeDealloc = NULL;
static IMP gOrigPasscodeViewDidAppear = NULL;

static void WGPasscodeDealloc(id self, SEL _cmd) {
    gWGPasscodeRecentlyShown = YES;
    WGForceResignKeyboard();
    if (gOrigPasscodeDealloc) {
        ((void (*)(id, SEL))gOrigPasscodeDealloc)(self, _cmd);
    }
}

static void WGPasscodeViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (gOrigPasscodeViewDidAppear) {
        ((void (*)(id, SEL, BOOL))gOrigPasscodeViewDidAppear)(self, _cmd, animated);
    }
    // 标记"密码页确实出现过"，供下面 didBecomeActive 兜底使用，
    // 避免对用户平时在聊天里正常打字的场景造成误伤。
    gWGPasscodeRecentlyShown = YES;
}

#pragma mark - 安装 hook

__attribute__((constructor))
static void WGKeyboardFixInit(void) {
    // 用字符串查类名，因为这是私有 Swift 类，没有公开头文件，
    // 找不到就安静跳过，不会导致 App 崩溃 (Whitegram/Telegram 版本更新后
    // 类名理论上可能变化，这样比较安全)。
    Class passcodeClass = NSClassFromString(@"_TtC10PasscodeUI23PasscodeEntryController");
    if (passcodeClass) {
        Method deallocMethod = class_getInstanceMethod(passcodeClass, sel_registerName("dealloc"));
        if (deallocMethod) {
            gOrigPasscodeDealloc = method_getImplementation(deallocMethod);
            method_setImplementation(deallocMethod, (IMP)WGPasscodeDealloc);
        }

        Method appearMethod = class_getInstanceMethod(passcodeClass, @selector(viewDidAppear:));
        if (appearMethod) {
            gOrigPasscodeViewDidAppear = method_getImplementation(appearMethod);
            method_setImplementation(appearMethod, (IMP)WGPasscodeViewDidAppear);
        }
    }

    // 兜底: App 回到前台 (Face ID 解锁应用锁通常会伴随这个通知触发)时，
    // 如果密码页最近确实出现过，再强制 resign 一次。
    // 这样即使上面 dealloc 因为某些 retain 被延迟触发，也有第二道保险。
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification * _Nonnull note) {
        if (gWGPasscodeRecentlyShown) {
            gWGPasscodeRecentlyShown = NO;
            WGForceResignKeyboard();
        }
    }];
}
