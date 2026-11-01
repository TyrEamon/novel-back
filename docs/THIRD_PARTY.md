# 第三方组件与分发条件

## 应用源码

基于 [MewX/light-novel-library_Wenku8_Android](https://github.com/MewX/light-novel-library_Wenku8_Android) 与原贡献者的工作。原始 [LICENSE](../LICENSE) 保留 GNU GPL version 2 或后续版本条款。本次 Flutter 组合版本按 [GPL version 3](../assets/licenses/GPL-3.0.txt) 分发，以兼容 LGPL v3 的协议适配代码。保留原署名、修改说明和构建脚本；发布 APK 时一并提供对应 Flutter 工程归档。

## 原版 API 运行库：libcpp.so

- 路径：`android/app/src/main/jniLibs/<abi>/libcpp.so`。
- 用途：0.3.x 文库联网接口的 JNI 运行库；**0.4.0 起不装入 APK，也不再调用**。
- 本分支不修改、不解包、不重新实现该二进制。
- 项目维护者于 2026-10-15 确认其可在**保持原样**的条件下再分发。本仓库据此保留原文件。
- 该组件的源码不在本工程中；不能将应用源码的 GPL 许可视为对该组件源码、修改权或其他用途的授权。需要超出原样再分发条件时，应联系原版权方。
- 原项目当前公开构建使用 [api-stub](https://github.com/MewX/light-novel-library_Wenku8_Android/blob/master/studio-android/LightNovelLibrary/settings.gradle)，因此本工程源码归档不应被描述为该二进制的完整对应源码。

历史文件保留原样。0.4.0 的自定义书源不依赖此运行库。

## 自定义书源规则引擎（0.4.0）

规则与请求解析适配自 gedoor 及 Legado 贡献者的 GPL-3.0 源码，固定到 [LegadoTeam/legado 3.26082823](https://github.com/LegadoTeam/legado/tree/3046111c1718e7b67c2ad468e54edf295ec05820)。原文许可、来源及修改说明保留在 [`third_party/legado`](../third_party/legado/README.md)。Flutter 仓库、网络、脚本宿主、持久化与管理界面由本工程接入；兼容范围见 [自定义书源](CUSTOM_SOURCES.md)。不附带第三方书源合集。

- [HtmlUnit core-js 5.3.0-legado.4](../third_party/htmlunit-core-js/README.md)：使用固定 Legado 提交中的原始 JAR；原始源码归档、MPL／Apache 等许可、修改差异和构建来源随项目保留，[完整声明](../assets/licenses/htmlunit-core-js.txt)。同版 E4X 和旧式 let／const 兼容代码一并移植。解释模式在后台执行，仅开放明确列出的解析与加密辅助 API，不开放任意 JVM 类与 Android 对象。
- [JsonPath 3.0.0 对应源码](https://github.com/json-path/JsonPath/tree/json-path-3.0.0)：Jayway 与贡献者，Apache-2.0，未修改；[许可](../assets/licenses/jsonpath.txt)。
- [Gson 2.14.0 对应源码](https://github.com/google/gson/tree/gson-parent-2.14.0)：Google，Apache-2.0，未修改；[许可](../assets/licenses/gson.txt)。
- [JsoupXpath 2.5.3](https://github.com/zhegexiaohuozi/JsoupXpath/tree/v2.5.3)、[Commons Text 1.13.1](https://github.com/apache/commons-text/tree/rel/commons-text-1.13.1)、[OkHttp 4.12.0](https://github.com/square/okhttp/tree/parent-4.12.0)、[AndroidX WebKit 1.14.0](https://developer.android.com/jetpack/androidx/releases/webkit#1.14.0)：Apache-2.0，未修改；[声明及许可](../assets/licenses/source-runtime.txt)。
- [Hutool core / crypto 5.8.22](https://github.com/dromara/hutool/tree/5.8.22)：Hutool 贡献者，MulanPSL-2.0，未修改；[完整声明](../assets/licenses/hutool.txt)。
- CryptoJS：直接使用上述固定 Legado 提交中的 `cryptojs.min.js`，未修改；Jeff Mott / Evan Vosberg，MIT，[原文许可](../assets/licenses/cryptojs.txt)。与原版登录 UI V2 协议、JS 数据转换代码一起接入书源运行环境。

Java 依赖版本固定于 `android/app/build.gradle.kts`，许可注册到应用的开源许可页。用户导入的书源规则与站点内容不属于本工程分发内容。

书源宿主新增的 [libarchive 1.1.6、简繁转换 0.2.17、ICU 检测与 Material 1.14.0](../third_party/source-host/README.md) 保留对应依赖许可与来源；[完整许可集合](../assets/licenses/source-host.txt) 注册到应用的开源许可页。

## 字体

应用不附带中文字体文件，默认使用系统字体。用户可导入自己的 TTF／OTF 字体，分别用于 App 和阅读器；导入文件保存在设备本地，不随项目分发。

## 在线听书协议

`lib/listening/edge_protocol.dart` 为 [rany2/edge-tts](https://github.com/rany2/edge-tts) v2 校验算法的 Dart 适配，参考提交 `bd44c1d1aaebdc1db7f47456ee12431b42ec7cac`，修改日期 2026-10-15。遵循 LGPL v3；[完整许可](../assets/licenses/edge-tts.txt) 与 GPL v3 原文随源码和应用提供。代码可在本工程中替换、修改后重新构建，构建不依赖私有密钥。

在线音色由 Microsoft Edge 在线语音服务提供。代码许可不授予该服务的所有权或可用性保证；不包含付费凭证。朗读会将待合成文本发送给该服务，缓存仅保留在设备本地。

## Flutter 与依赖包

### MOBI 导入：libmobi

使用 [libmobi 0.12](https://github.com/bfabiszewski/libmobi/tree/v0.12)，Copyright 2014–2022 Bartek Fabiszewski，LGPL-3.0-or-later。完整、未修改的上游源码与许可在 `third_party/libmobi/`；Android 以独立 `libmobi.so` 动态链接，应用导出与 JNI 适配位于 `android/app/src/main/cpp/`，CMake 构建不启用加密支持。修改或替换库后可使用同一工程重新构建。源码导出包含库源码和构建脚本，应用开源许可页包含 LGPL v3 与 GPL v3 原文。

MOBI 在本机重建为 EPUB 后使用现有阅读器，不访问转换服务，不解密 DRM 文件。

### 文档导入

Android 文档转换使用 [jsoup 1.16.2](https://jsoup.org/)（MIT，Jonathan Hedley）、[commonmark-java 0.30.1](https://github.com/commonmark/commonmark-java)（BSD-2-Clause，Atlassian）和 [PDFBox Android 2.0.27.0](https://github.com/TomRoush/PdfBox-Android)（Apache-2.0，Tom Roush / Apache Software Foundation）。PDFBox 的 Bouncy Castle 1.72 依赖遵循 MIT-style 许可。Android 旧版本兼容使用 Google 的 `desugar_jdk_libs_nio` 2.1.5（GPL-2.0 with Classpath Exception）。固定版本列于 `android/app/build.gradle.kts`，原文与 PDFBox / FontBox 声明保存在 `assets/licenses/` 并注册到应用许可页。FB2 / DOCX 的 SAX 转换与 RTF 正文导入为本工程实现。

OpenJDK 兼容库的完整未修改源码、许可与构建脚本保存在 `third_party/desugar-jdk/source-2.1.5.tar.gz`，对应上游发布准备提交 `73170c345e6a762fc6a1f0301bb15218850023ef`；来源与解压方式见 `third_party/DESUGAR_JDK_LIBS.md`，随应用对应源码一起提供。

依赖版本锁定于 `pubspec.lock`。Flutter、Cupertino Icons、音频与存储插件保留各自许可；Flutter 构建生成的许可集合可在 **我的 → 关于纸间文库 → 开源许可与字体授权** 查看。该页面也包括上述协议适配声明。

液态玻璃基于 [liquid_glass_easy 5.0.0](https://pub.dev/packages/liquid_glass_easy/versions/5.0.0)，作者 Ahmed Gamil，使用 MIT License。源码和原许可保留于 [`third_party/liquid_glass_easy`](../third_party/liquid_glass_easy)；本地 GPU 性能修改单独记录在 [`PATCHES.md`](../third_party/liquid_glass_easy/PATCHES.md)。应用保留原作者署名，版权与许可随源码及 Flutter 的开源许可集合分发。

## 内容与展示图

中文显示使用 [OpenCC ver.1.1.9](https://github.com/BYVoid/OpenCC/tree/ver.1.1.9) 的原始字词典（BYVoid 及贡献者，Apache-2.0）。词典及来源说明位于 `assets/opencc/`，完整许可位于 `assets/licenses/opencc.txt`，注册到应用开源许可页。区域字形转换与有界缓存由 Dart 实现，不包含 OpenCC 原生二进制。

TXT / EPUB 目录解析、图片尺寸样式与同步归档使用 `archive`（MIT）、`html`（MIT）及 `csslib`（BSD-3-Clause），版本保留于锁文件，许可包含在 Flutter 生成的开源许可集合中。应用使用本项目选定的奶白人物剪影图标，原始位图与适配信息保留于 `assets/branding/`，不包含莱茵生命标志或宣传片素材。

小说、封面、插图归各自权利人所有，不包含在源码许可中。README 展示图使用独立演示数据、程序绘制封面，不包含个人账号、阅读记录或真实设备通知。
