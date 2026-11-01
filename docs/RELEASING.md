# 整理公开版本

在项目根目录执行：

```sh
python3 tools/export_public_source.py ../Wenku8_Flutter-release
```

生成目录可作为 GitHub 上传的 Flutter 源文件。继续使用原 Fork 时，保留原仓库的历史与署名，将对应文件加入现有仓库即可。导出保留 Flutter 源码、测试、资源、平台工程和许可，排除本机路径、密钥、真机截图与日志、语音探测工具、内部开发记录、旧版 Android 构建目录和独立性能探针。目标目录必须为空，脚本不会覆盖现有文件，也不会执行 Git 操作。

## 先保留许可与第三方条件

原项目 `LICENSE` 保留 GPL version 2 或后续版本条款；本 Flutter 组合版本使用 GPL version 3，以兼容 LGPL v3 的在线语音协议适配。发布时提供 Flutter 工程归档、原始 `LICENSE`、`NOTICE`、`assets/licenses/` 和第三方对应源码，保留署名和修改日期。不要将衍生项目改标为仅有 MIT 或 Apache 许可。完整来源见 [第三方组件与条件](THIRD_PARTY.md)。

0.4.0 不附带中文字库；协议适配保留 LGPL v3。阅读 3 规则解析器的上游 GPL v3 源码、版本与修改说明须随对应源码提供，位于 `third_party/legado/`。OpenJDK 完整源码归档及其来源文件、其他依赖许可也须包含在导出中。

## 0.4 的内容与宣传审查

本版本只开发通用书源导入、规则解析与阅读能力，不内置内容来源，不推荐、分发侵权源，不为侵权来源提供针对性适配。通用回归使用自编文档和本地测试服务。

在发布者批准公开版本前，逐项核对并记录实际候选的结果：

- 新装空数据启动不附带书源、合集、订阅或内容站点入口；导入前不执行规则脚本，书源保存经过明确确认。旧记录与已有缓存不能成为重新启用内置接口的入口。
- 源码归档与 APK 不包含用户规则、登录资料、Cookie、抓取的正文、未经授权的书籍封面／插图或专用内容代理；截图、演示与文档只使用自编、已获授权或可依法使用的材料。
- README、更新说明、镜像介绍页、宣传片和截图应对应实际可用功能。分别说明规则语法兼容、宿主 API 和站点服务的条件，不以“导入成功”宣传为“全面兼容”，不承诺版权、安全或站点可用性。
- 应用的「关于」与导入确认页可打开[使用与风险声明](RESPONSIBLE_USE.md)。入口和声明不得替代对实际功能、材料授权及第三方许可的核查。
- 针对权利反馈，先核实项目控制范围内的具体材料和功能，再采取相应处理，不向公开 Issue 索取账号凭据或整本受保护作品。

`export_public_source.py` 会排除本地资料、旧宣传截图、专用内容网关及已退役的 `libcpp.so`。历史工作区内的二进制原样保留，但不属于 0.4 的 APK 或公开源码归档。原文件的历史许可说明见 `NOTICE`，不能用于推导第三方内容授权。

```sh
python3 tools/export_public_source.py ../Wenku8_Flutter-release
python3 tools/check_public_source.py ../Wenku8_Flutter-release
python3 tools/verify_apk_runtime.py build/app/outputs/flutter-apk/app-release.apk --abi arm64-v8a
```

结构与脱敏检查不能判断第三方材料的授权。发布者仍需完成上面的材料和宣传审查后，才能将草稿公开。

## 签名与构建

Flutter 3.41.5、Dart 3.11.3、JDK 17、Android SDK。源码包中保留的 Gradle wrapper 用于复现构建；Flutter、Gradle 及依赖首次构建需要下载。

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 \
  --split-debug-info=build/symbols/local/arm64-v8a
python3 tools/analyze_apk_size.py build/app/outputs/flutter-apk/app-release.apk \
  --output build/apk-size-arm64-v8a.json
cd android
./gradlew :app:testReleaseUnitTest
```

未配置签名时输出为本地预览包，使用调试证书。正式分发前，在本机创建 `android/key.properties`，设置 `storeFile`（相对于 android 的路径或绝对路径）、`storePassword`、`keyAlias`、`keyPassword`，使用自己的签名证书。密钥文件和 keystore 已加入忽略规则，不要上传。

同一包名的后续升级必须使用同一签名证书。当前包名为 `org.mewx.wenku8_flutter`；修改包名会创建独立应用，不能直接沿用原应用的数据。

调试符号保存在 `build/symbols/`，不放入 APK。保留与每次 APK 对应的符号文件；定位压缩后的 Dart 调用栈时使用 `flutter symbolize`。体积报告分别统计 APK 下载字节与各文件解压字节，不把符号移出包体算作功能裁减，也不通过压缩原生库来增加设备端的解压副本。

自动化检查验证通用规则、代码与构建；第三方服务的可用性不作为本项目的兼容承诺。

## 用 GitHub Actions 构建 APK

在 GitHub 打开 **Actions → Build Android APKs → Run workflow**。构建完成后，在该次运行的 **Artifacts** 下载压缩包，内含 ARM64、ARMv7、x86_64 APK、源码 ZIP 和本版说明。无需开通付费语音或更新服务。

三个架构分别构建，保持相同构建号；每个 APK 的符号与体积报告另存为 `symbols-and-size` Artifact，保留 90 天，不随 Release 附件分发。正式保留版本时也应自行归档相应符号。

手动运行未配置签名时使用临时 Runner 的调试证书，只用于预览；它不能保证覆盖上次安装。要持续升级，先在仓库 **Settings → Secrets and variables → Actions** 配置同一套长期签名：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的 Base64 内容 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |
| `ANDROID_STORE_PASSWORD` | keystore 密码 |

不要把签名文件或这些值提交到 Git；工作流只在临时目录解码，任务结束清除。已有本地预览版必须使用原来的签名才能覆盖；改用新签名以前先导出阅读记录，不要直接卸载现有应用。

## 发布一个可被应用检测的版本

自 0.4.0 发布起，官方渠道撤下 0.4.0 之前版本的所有 APK，包括 Release 附件与 Actions 中包含 APK 的历史产物。保留对应 `source.zip`、历史发布记录、Git 标签与代码历史，不删除整条 Release。更新镜像在缓存读取前拒绝旧 APK，防止旧缓存继续分发。清理前记录附件清单，并确保历史产物中的源码已有独立归档。

1. 更新 `pubspec.yaml` 的版本号和更大的 Android 构建号，并同步 `lib/updates/app_updates.dart` 的本版说明与版本常量。
2. 在 `CHANGELOG.md` 添加对应版本的说明，并同步 `lib/updates/release_highlights.dart` 的精简摘要与详细分类。详细说明按实际功能、界面与操作、修复和性能分组；按钮或入口迁移要写清位置和使用方式。应用按安装版本名与构建号记录已完成阅读的说明，不依赖联网检查开关。运行 `python3 tools/prepare_release.py --tag v0.4.0 --notes build/release-notes.md` 可检查当前版本与标签是否一致。
3. 完成内容与宣传审查，并取得发布授权后，提交到自己的 Fork，推送与版本一致的标签。本地整理脚本不会提交或推送。
4. Actions 完成检查和三架构构建，上传 APK / 工程源码并创建 **Draft Release**。先核对签名、工程归档、脱敏与第三方条件，再点击 **Publish release**。
5. 已安装应用会在下次前台检查时显示新版本；也可以在「关于纸间文库」立即检查。草稿、预发布和普通 Actions Artifacts 不进入自动更新渠道。

正式标签构建缺少四项签名配置时会直接失败，不会用每次变化的临时证书发布更新。重跑只可替换草稿附件，不覆盖已发布版本；有修订时增加版本号再发布。

面向已有用户的正式更新使用 `vX.Y.Z` 标签，并递增版本名与构建号。0.2.4 及更早客户端不能匹配 GitHub 对 `+构建号` 编码后的下载地址，不要将这类标签用于兼容旧版的稳定更新渠道。不要移动已推送的版本标签。

更新源默认为 `mikufoxxx/Wenku8_Flutter`。发布工作流将 `${{ github.repository }}` 写入 `UPDATE_REPOSITORY`，因此他人 Fork 的构建检查自己的 Releases。本地构建可用 `--dart-define=UPDATE_REPOSITORY=用户名/仓库名` 指定。应用不包含 GitHub Token，不收集账号或阅读内容；自动检查可关闭。

下载使用 HTTPS 和受限的 GitHub 资源地址，使用 GitHub 提供的 SHA-256 摘要（如有）核验完整性。每次下载写入独立缓存目录，交给系统的文件与 Content URI 不再被后续下载替换。完成下载与打开安装程序前均核对 Android 包名、真实版本、构建号及签名；安装页显示已验证的版本与构建号，首次安装授权及最终确认由系统界面完成。检查、下载、安装互斥；下载可取消，断线或校验失败后可重新下载。

### 更新链路回归

`flutter test test/app_updates_test.dart test/app_update_prompt_test.dart test/release_highlights_test.dart` 覆盖并发排除、版本／附件绑定、不可变文件路径、安装授权和失败重试，以及本版说明优先展示、分页完成记忆与新构建再次展示。

真机测试使用独立的 `.render_probe` 包，不覆盖正式版。`tools/create_update_fixtures.py --sdk "$ANDROID_HOME" --output build/update-fixtures` 可生成调试签名的微型 APK；将输出放入测试包的 `files/update-fixtures/` 后，以 `fixture=update` 运行 `SessionFixtureInstrumentation`，核对真实包解析与 FileProvider 读取的版本。`integration_test/update_install_probe.dart` 可作为 debug 入口构建（版本覆盖为 `0.3.3+35`），通过真实的更新页操作完成 `0.3.4+36` 安装验证。该入口只接受隔离测试包；正式构建仍使用 `lib/main.dart`。
