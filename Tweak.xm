// WGKeyboardFix.xm
//
// 修复目标: Whitegram (ph.telegra.Telegraph.wge) 在 FaceID/密码解锁后
// 键盘无法收回 / 输入框错误聚焦在锁屏密码框上的问题。
//
// 静态分析结论 (对 TelegramUIFramework.framework 逆向得出):
//   - 密码解锁页面对应的类是 Swift 类 PasscodeUI.PasscodeEntryController,
//     其 ObjC 可见名称为 _TtC10PasscodeUI23PasscodeEntryController
//   - 该模块内的输入框节点 PasscodeInputFieldNode 只导出了 activate()
//     (对应 becomeFirstResponder), 没有导出任何 deactivate / resign 类方法。
//   - EntryController 本身也没有重写 viewDidDisappear:。
//   => 密码框在解锁后被移出屏幕时，没有一条可靠路径主动交还第一响应者，
//      导致键盘残留 / 后续页面聚焦异常。
//
// 修复策略 (不依赖对具体私有实现的猜测，只在"密码页确实出现过"时才触发,
// 避免误伤用户在聊天里正常打字的场景):
//   1. Hook PasscodeEntryController 的 -dealloc (Swift NSObject 子类的
//      deinit 保证会走到这里，是最稳定、跨版本兼容性最好的收尾点)，
//      在这里强制清空当前第一响应者 + 收起键盘。
//   2. 用一个全局标记记录"密码页最近出现过"，在 UIApplicationDidBecomeActive
//      时做一次兜底强制 resign（覆盖 dealloc 因为某些retain cycle被延迟触发的情况）。
//   3. 强制 resign 使用系统公开 API 的经典技巧:
//        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder)
//                                                     to:nil from:nil forEvent:nil];
//      这个调用会让 UIKit 自己去找当前真正的第一响应者并让它 resign，
//      不需要我们知道它具体在哪个 window / 哪个 UITextField 上，
//      所以即使密码框已经不在可见层级里也依然有效。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gWGPasscodeRecentlyShown = NO;

static void WGForceResignKeyboard(void) {
    // 全局强制交还第一响应者，触发系统收起键盘。
    // 用 sendAction 而不是直接操作 keyWindow，因为密码页可能用的是
    // 独立的覆盖 window，这个 window 隐藏后已经不在 UIApplication.windows
    // 里能方便枚举到的状态了，但 sendAction 走的是 UIKit 内部维护的
    // 第一响应者引用，不受此影响。
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder)
                                                    to:nil
                                                  from:nil
                                              forEvent:nil];

        // 双保险: 顺便对当前 keyWindow 也调用一次 endEditing。
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
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

// ---- Hook 1: 密码页 dealloc 时立刻清理 ----
// 用字符串类名 hook，因为这是私有 Swift 类，没有公开头文件。
%hook _TtC10PasscodeUI23PasscodeEntryController

- (void)dealloc {
    gWGPasscodeRecentlyShown = YES;
    WGForceResignKeyboard();
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // 密码页确实显示过，为后面的兜底通知做标记
    gWGPasscodeRecentlyShown = YES;
}

%end

// ---- Hook 2: App 恢复前台时的兜底 ----
// 覆盖 dealloc 因为动画/转场导致延迟触发、或者 Face ID 走的是完全
// 不经过这个类销毁流程的路径（例如某些系统级生物识别 fallback）的情况。
%hook UIApplication

- (void)_notifyAppWasActivated {
    %orig;
    if (gWGPasscodeRecentlyShown) {
        gWGPasscodeRecentlyShown = NO;
        WGForceResignKeyboard();
    }
}

%end

%ctor {
    // 也用标准公开通知再挂一层，双重保险，防止上面私有选择器
    // _notifyAppWasActivated 在某个 iOS 版本上改名/消失。
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
