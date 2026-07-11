#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gWGPasscodeRecentlyShown = NO;

static void WGForceResignKeyboard(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder)
                                                    to:nil
                                                  from:nil
                                              forEvent:nil];

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
    gWGPasscodeRecentlyShown = YES;
}

__attribute__((constructor))
static void WGKeyboardFixInit(void) {
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
