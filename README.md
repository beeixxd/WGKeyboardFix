# WGEKeyboardFix

## 问题

WGE 开启应用锁（FaceID / 密码）后，从锁屏状态用 FaceID 解锁回到 App 时，
偶尔会出现键盘卡住收不回去的情况：

- 键盘拉出来之后怎么点都收不回去
- 打开一个对话后，即使没点任何输入框，输入框却自己展开到屏幕中间，但键盘位置是空白的
- 主页会留有半个键盘形状的阴影空白区域
- 唯一能打断这个状态的办法是手动点一下搜索框或对话框，把焦点从残留的密码输入框上抢过来

## 原因

密码解锁页面被关闭、挪出屏幕的时候，那个密码输入框并没有主动把"第一响应者"
（也就是键盘当前对应的输入焦点）交还出去。它人已经不在屏幕上了，但系统仍然
认为它是当前应该弹出键盘的对象，导致键盘卡在一个"找不到主人"的孤立状态。

## 这个插件做了什么

在密码解锁页面真正销毁的那一刻，强制让当前持有输入焦点的对象交还焦点、
收起键盘；并且在 App 从后台恢复到前台时，如果检测到密码页最近确实出现过，
再做一次兜底强制收起，双重保险，避免上面这几种卡键盘的情况。

# WGEKeyboardFix

## The Problem

After unlocking WGE's in-app lock (Face ID / passcode) and returning
to the app, the keyboard occasionally gets stuck:

- The keyboard appears and won't dismiss no matter what you tap
- Opening a chat causes an input field to expand to the middle of the
  screen on its own, even without tapping it, while the keyboard area
  stays blank
- The home screen is left with a keyboard-shaped shadow/blank area at
  the bottom
- The only way to break out of this is to manually tap the search bar or
  a chat, stealing focus away from the leftover passcode input field

## Root Cause

When the passcode lock screen is dismissed and removed from view, the
passcode input field never actively hands back "first responder" status
(i.e. the current keyboard focus target). It's no longer visible, but the
system still thinks it's the thing that should have the keyboard, so the
keyboard ends up stuck in an orphaned state.

## What This Fix Does

The moment the passcode screen is actually deallocated, it forces
whatever currently holds keyboard focus to give it up and dismiss the
keyboard. As a second safety net, when the app returns to the foreground
and the passcode screen was recently shown, it forces the same dismissal
again — covering both of the scenarios above.

# WGKeyboardFixE

## Проблема

После разблокировки внутренней блокировки приложения WGE (Face ID /
пароль) и возврата в приложение клавиатура иногда застревает:

- Клавиатура выезжает и не скрывается, сколько ни нажимай
- При открытии чата поле ввода само разворачивается в середину экрана,
  даже без нажатия на него, при этом область клавиатуры остаётся пустой
- На главном экране остаётся пустая область в форме тени от клавиатуры
- Единственный способ выйти из этого состояния — вручную нажать на
  строку поиска или на чат, чтобы перехватить фокус у оставшегося поля
  ввода пароля

## Причина

Когда экран ввода пароля закрывается и убирается с экрана, поле ввода
пароля так и не отдаёт активно статус "first responder" (то есть текущую
цель фокуса клавиатуры). Его уже не видно, но система по-прежнему
считает, что клавиатура должна показываться именно для него — из-за
этого клавиатура застревает в "осиротевшем" состоянии.

## Что делает это исправление

В момент фактического уничтожения экрана ввода пароля принудительно
заставляет текущего обладателя фокуса клавиатуры отдать его и скрывает
клавиатуру. В качестве второй подстраховки: когда приложение возвращается
на передний план и экран пароля недавно показывался, выполняется
повторный принудительный сброс фокуса — это покрывает оба описанных
выше сценария.
