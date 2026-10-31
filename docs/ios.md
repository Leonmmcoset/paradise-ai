# iOS 支持与兼容性审查

## 平台与构建环境

- 最低 iOS 15.0，支持 iPhone 和 iPad。
- 真机使用 ARM64；模拟器支持 Apple Silicon ARM64 和 Intel x86_64。
- Bundle ID：`fan.x0.para`。
- 使用 Flutter 3.47.5 stable（与 CI 一致）、macOS、Xcode 26 或更高版本、已安装的 iOS SDK/模拟器运行时和 CocoaPods。当前 `workmanager_apple` 引用了 iOS 26 SDK 的类型，因此 Xcode 16.4 无法编译；应用最低运行版本仍为 iOS 15。CI 明确选择 Xcode 26.3。
- 需要 Rust stable 和三个目标：`aarch64-apple-ios`、`aarch64-apple-ios-sim`、`x86_64-apple-ios`。OII 的构建钩子调用 Cargo、`xcrun clang` 和对应的 Apple SDK。
- 项目使用 CocoaPods，并在 `pubspec.yaml` 中关闭 Swift Package Manager，确保 Typst 的 podspec 和权限编译宏生效。运行 `pod install` 后产生的 `ios/Podfile.lock` 应随首次在 Mac 上验证的依赖解析结果提交。

在 Mac 上准备并运行：

```bash
flutter pub get
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
dart run typst_flutter:setup
python3 tool/check_ios_native.py
bash tool/run_ios_smoke.sh
flutter run -d <设备ID>
```

`run_ios_smoke.sh` 自动选择已安装运行时中的 iPhone 模拟器，也接受 UDID：`bash tool/run_ios_smoke.sh <UDID>`。如果 Typst 下载失败后留下了版本标记，运行 `dart run typst_flutter:setup --force`，然后重新检查。首次下载需要访问该库的 GitHub Releases。

模拟器和未签名构建不需要开发者证书。真机调试需要在 `ios/Runner.xcworkspace` 的 Runner → Signing & Capabilities 中选择自己的 Team，并按需修改 Bundle ID。

## 未签名 IPA 与 CI

```bash
bash tool/build_unsigned_ipa.sh
```

脚本执行 `flutter build ios --release --no-codesign`，检查 ARM64、OII 框架、发布二进制中的 OII/Typst/RaTeX FFI 导出，以及主 App 没有签名和 provisioning profile，再将 `Runner.app` 打包为标准的 `Payload/Runner.app` IPA：

```text
build/ios/ipa/paradise-<版本>-ios-unsigned.ipa
```

CI 的 `build-ios` 作业在 `macos-15` 上执行依赖准备、iPhone 模拟器集成测试和未签名 Release 构建。推送 main、向 main 提交 PR 或手动触发 CI 均会运行。下载 Actions artifact **`paradise-ios-unsigned-ipa`**，保留 14 天。此产物需要另行签名才能安装到真机；App Store/TestFlight 的签名与分发需要自己的 Apple 开发者配置。

## 功能与依赖检查

审查依据为 `pubspec.lock` 中的依赖、插件的 iOS 实现及 podspec、Dart 调用路径和新增的原生集成测试。没有新增生产依赖。

| 功能 / 直接依赖 | iOS 处理与验证范围 |
| --- | --- |
| 聊天、人设、记忆、Agent、世界书、提示词和协议客户端 | Dart/Flutter 代码，复用现有单元测试；模拟器测试启动完整 App。HTTP、流式响应、MCP 和远程备份走 Dart 网络接口。 |
| `flutter`、`flutter_localizations`、`intl`、`characters` | Flutter UI、英文/简体/繁体本地化；补齐 iOS 状态栏亮度和三语系统权限说明。 |
| `http`、`path`、`glob`、`crypto`、`archive`、`timezone` | 纯 Dart；保留跨平台实现。用户可自配 HTTP、局域网服务，因此 Info.plist 声明了 ATS 网络策略和本地网络用途。 |
| `shared_preferences`、`sqflite`、`path_provider` | 使用各自的 Apple 插件。模拟器测试实际偏好持久化、SQLite 读写和沙盒目录。 |
| `image_picker`、`photo_manager`、`file_picker` | 相机/相册用途已声明，照片权限支持系统的有限图库授权。头像、附件和缩略图先复制到 Documents；PHAsset ID 转义后用作文件名；照片导出使用适合显示和上传的 JPEG。文档导入/导出使用系统文件选择器。相机和 iCloud 文件交互需真机验收。 |
| `video_player` | 使用 AVFoundation。视频附件仍使用原始视频；能否解码取决于 iOS 支持的容器与编码，需用实际素材验收。 |
| `geolocator`、`flutter_contacts`、`permission_handler` | 配置前台定位与联系人用途说明；geolocator 不申请 Always 定位。permission_handler 仅启用应用用到的照片、通知宏。模拟器验证插件注册与权限状态读取；系统授权流程需人工验收。 |
| `flutter_local_notifications`、`workmanager` | 通知使用 Darwin 配置，启动不弹授权框。注册 `lib3.proactive.sweep` 的 BGAppRefresh 任务、插件回调、允许标识和 fetch 后台模式。模拟器验证通知初始化及后台插件注册。 |
| `flutter_tts`、`just_audio` | 系统 TTS 设置 iOS 音频会话，并按已安装语音解析 identifier/locale。远程 TTS 仍缓存文件后由 AVFoundation 播放。模拟器测试读取语音列表、解码真实 WAV；实际发声、静音开关和不同音频格式需真机验收。 |
| `webview_flutter`、`url_launcher` | 分别使用 WKWebView 和系统外部链接。模拟器测试加载 HTML 并执行 JavaScript；HTML/SVG 卡片与文件预览复用现有代码。 |
| `flutter_svg`、`flutter_highlight`、`highlight`、`flutter_math_fork` | Dart/Flutter 绘制与文本处理，复用原有实现和测试。 |
| `terminal_view`（本地维护版本） | Flutter 终端绘制代码可以编译；本地终端所需的 PRoot 运行时仅支持 Android，iOS 隐藏终端入口。 |
| `oii_bridge`（本地 Rust 库） | 按真机/模拟器分别选择 Rust ABI 和 SDK，输出 dylib；Dart 通过 `@Native` 加载 Flutter 打包的 code asset。模拟器测试解释器、工作 isolate、宿主回调和备份验证；Release 打包检查导出符号。 |
| `ratex_flutter` | 上游 XCFramework 包含真机 ARM64、模拟器 ARM64/x86_64，podspec 保留 FFI 入口。模拟器实际解析公式，Release 打包检查符号。 |
| `typst_flutter` | 使用上游发布的静态 XCFramework。Podfile 生成本地源码 podspec，复制少量 C 包装源码，并移除上游 3.0.0 无效的绝对 `vendored_frameworks` 声明；不修改 pub 缓存。直接链接 SDK 对应的原始静态库切片，兼容真机/模拟器库文件名不同的情况，并显式保留 19 个 FFI 入口，避免符号被省略。准备脚本检查全部切片；模拟器实际编译离线 CeTZ 绘图和 CJK 字体，Release 打包检查符号。 |

开发依赖 `flutter_test`、`integration_test`、`file_picker_platform_interface`、`path_provider_platform_interface`、`sqflite_common_ffi` 仅用于测试/验证，不提供额外产品功能。

## iOS 系统约束

### 工作区

标准 iOS 沙盒无法运行 Android 的 PRoot/ptrace、Linux rootfs 和任意本地子进程。iOS 不安装或探测 PRoot、不监听其平台通道，并隐藏本地终端入口。依赖环境的 `shell`、`view_image` 工具不向模型提供，也不会因恢复了 Android 的就绪状态而启用。

工作区目录、文件浏览器、预览、写入审批及六个文件工具仍然可用：`read_file`、`write_file`、`edit_file`、`list_dir`、`glob`、`grep`。远程 HTTP/SSE MCP 服务可用；需要启动本地进程的服务受上述限制。

### 数据与备份

iOS 更新或恢复可能改变沙盒容器 ID。载入持久化数据时，程序将旧 Documents 路径重新定位到当前容器，覆盖头像、附件、缩略图、贴纸、壁纸和工作区路径。选择器缓存会复制到 Documents，避免缓存被清理后消息丢失附件。

自动备份与完整备份写入 Documents/backup，可通过系统“文件”App 或 Finder 文件共享访问。**卸载 App 会删除这些本地数据及备份**。需要跨卸载保留时，请使用设置中的导出功能保存到 App 外部，或配置远程备份。设置中的 iOS 说明已反映这一行为。

### 后台与通知

iOS 自行决定后台刷新机会，15 分钟只是最早执行提示，不能保证按该周期唤醒。用户强制结束 App、关闭后台刷新、省电或系统限制，都可能阻止后台请求和主动消息生成。已交给系统的本地通知与后台联网是不同机制；通知是否展示也受用户授权、专注模式和系统待发通知数量限制影响。

## 验证边界与真机验收

本地开发环境为 Linux，Flutter 3.47.8，执行 Dart 分析、完整 Flutter 单元/组件测试、OII 的宿主 FFI 测试、原生库切片审查及工程/脚本结构检查。Xcode 编译、iOS 模拟器原生集成测试和未签名 IPA 验证由 macOS CI 执行，以对应提交的 CI 结果和构建产物为准。**尚未进行有签名的真机验收**。

发布前仍需在有签名的 iPhone/iPad 上确认：

- 首次启动、中文/英文权限说明、拒绝后重新授权、有限图库选择、相机、iCloud 文档导入和导出。
- 图片、GIF、HEIC 导出、视频、系统/远程 TTS 与不同音频编码，含静音开关和音频中断。
- 聊天流式请求、HTTP/局域网 AI 与 MCP、远程备份，在实际网络和系统权限下可用。
- 通知授权、前台/后台通知、后台刷新机会及强制退出后的行为。
- 升级、重新签名或恢复后的持久媒体路径，以及导出备份后恢复完整数据。
