# 荧光阅读

一个配合 BetterMouse 使用的 Mac 小程序：在鼠标附近显示一条半透明荧光条，随鼠标移动，帮助阅读时聚焦当前一行。

## 使用

1. 双击 **荧光阅读.app**，荧光条立即显示。再次打开同一个 app，荧光条关闭；再打开就重新显示。
2. 在 **BetterMouse** 中，把侧键绑定为**打开这个应用**。这样按一下显示，再按一下关闭。侧键由 BetterMouse 管理，荧光阅读本身不监听侧键，也不申请辅助功能权限。
3. 点击顶部菜单栏的**荧光笔图标 → 设置…**，可以调节长度、粗细、透明度和颜色，也能选择整屏横条。关闭设置窗口后仍可继续使用。

另一个绑定方式：把 BetterMouse 的侧键设为发送 **⌃ Control + ⌥ Option + ⌘ Command + H**。程序运行时，这个快捷键也能开关高亮。如果被其他程序占用，设置窗口会提示；“打开应用”方式仍可使用。

默认是黄色荧光条，长 420、粗 28 逻辑像素、透明度 30%。高亮条允许点击穿透，可以照常选字、点击和滚动。鼠标靠近屏幕边缘时，荧光条会留在当前屏幕内。

它是临时屏幕覆盖层，不会保存为 PDF 批注；屏幕共享或截图可能包含它。屏幕休眠时自动关闭，需要时再打开即可。

## 退出

点击菜单栏**荧光笔图标 → 退出荧光阅读**，程序即完全退出。

## 文件与兼容性

适用于 Apple 芯片 Mac、macOS 13 或更新版本。在本机编译并采用临时签名，供这台 Mac 试用。建议先把文件夹放在固定位置，再在 BetterMouse 里绑定。

`Source` 内附完整 Swift 源代码。装有 Apple Command Line Tools 时，可运行 `zsh Source/build.sh` 重新构建。程序无第三方依赖，不联网，不读取文献文件，不记录键盘输入；只保存外观设置。

## 下载

[下载 macOS Apple 芯片试用版](https://github.com/jayne210/reading-highlighter/releases/latest/download/ReadingHighlighter-1.0-macOS-arm64.zip)。解压后运行里面的“荧光阅读.app”。

## 构建

需要 Apple 芯片 Mac、Xcode Command Line Tools 和 Python 3。在仓库根目录运行：

```sh
zsh Source/build.sh
```

应用生成在仓库根目录。代码采用 Swift / AppKit 编写，使用 macOS 原生窗口显示可点击穿透的覆盖层。

当前为个人试用版本，已完成编译和屏幕定位逻辑检查；实际阅读效果及 BetterMouse 配合效果由使用者试用确认。应用使用本地临时签名，尚未经过 Apple 公证。
