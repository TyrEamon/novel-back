<p align="center">
  <img src="assets/branding/app-icon.png" width="88" alt="纸间文库图标" />
</p>

<h1 align="center">纸间文库</h1>
<p align="center">自己的书源，自己的阅读空间。</p>

<p align="center">
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/releases/latest"><img src="https://img.shields.io/github/v/release/mikufoxxx/Wenku8_Flutter?style=flat-square&color=555555" alt="最新版本" /></a>
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/actions/workflows/flutter-ci.yml"><img src="https://github.com/mikufoxxx/Wenku8_Flutter/actions/workflows/flutter-ci.yml/badge.svg?branch=master" alt="构建状态" /></a>
  <img src="https://img.shields.io/badge/Android-7.0%2B-555555?style=flat-square" alt="Android 7.0 及以上" />
  <a href="assets/licenses/GPL-3.0.txt"><img src="https://img.shields.io/badge/License-GPL--3.0-555555?style=flat-square" alt="GPL 3.0" /></a>
</p>

<p align="center">
  <a href="https://git.3952039.xyz/#releases">下载应用</a> ·
  <a href="CHANGELOG.md">更新日志</a> ·
  <a href="docs/CUSTOM_SOURCES.md">书源使用指南</a> ·
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/issues">问题反馈</a>
</p>

> [!IMPORTANT]
> **自 0.4.0 起，纸间文库为「零内置书源」版本。**
>
> **不附带任何书源、书源合集或推荐订阅。在线阅读需自行导入可信、合法且有权使用的书源；本地阅读可直接使用。**
>
> **即日起，官方渠道不再提供 0.4.0 之前任何版本的安装包，包括历史正式版、测试版及预览版，不再提供旧版下载或补发。历史源码归档继续保留。**

## 为每一页，留一个舒服的位置

纸间文库是一款面向 Android 手机与平板的阅读应用。奶白玻璃、档案式排版和立体书架贯穿界面；从自己的书源发现作品，也可以把本地图书整理成随身书库。

### 按自己的习惯阅读

- **三种阅读方式**：上下滚动、横排翻页、竖排翻页；平板与折叠屏支持展开双页。
- **细致的排版调整**：字号、行距、四边页边距、段落间距、首行缩进和两端对齐，调整时直接预览正文。
- **熟悉而连贯的动效**：逐段接续、平移、覆盖、纸页翻动或无动画，自由选择。
- **自己的阅读外观**：阅读配色、背景图和自定义字体；App 与阅读器字体可分别设置。
- **随手留下书签**：长按选择句子、复制或收藏，回到原文时定位高亮，也可将摘录保存为带图标水印的图片。
- **完整的阅读工具**：分卷目录、章内查找、进度拖动、音量键翻页、自动滚动、跨章衔接，以及封面与插图缩放、查看和保存。

### 把自己的书整理好

- **立体书架与列表**：支持惯性浏览、吸附和触觉反馈，也可切换为纯列表。
- **统一整理**：自定义分类，按阅读状态与书籍来源筛选；本地书库可独立显示，也可与书架合并。
- **多格式导入**：TXT、EPUB、MOBI／AZW／AZW3／PRC、FB2、PDF、DOCX、RTF、HTML、Markdown 与 ZIP。
- **扫描后自己选择**：扫描可访问的共享存储或指定文件夹，先筛选、勾选，再确认导入。
- **同系列分卷合并**：多选导入、统一确认合并，保留目录、插图和阅读记录；支持批量整理与删除。
- **本地与网盘**：支持 OpenList／WebDAV、夸克网盘导入，以及通过兼容的系统云文档入口手动合并同步原书和阅读记录。详见[网盘导入指南](docs/CLOUD_IMPORT.md)。

### 书源与听书，由你选择

- **兼容阅读 App 3.0 小说书源**：支持常见 JSON 与脚本型小说书源，覆盖搜索、发现分类、书籍详情、分卷目录、正文和插图，以及书源提供的登录与网页验证流程。
- **书源管理**：文件、链接或粘贴导入，预览后选择；支持分组、编辑、排序、启停、检查与导出。
- **跨源搜索**：可指定书源或同时搜索全部启用书源，支持简繁及港／台常见字形匹配。
- **账号状态可见**：登录信息按书源分别管理；明确支持的书源可验证登录、合并云书架或手动签到。
- **在线听书**：中文音色、自定义语音接口、0.5～3 倍速、段落跟随、睡眠定时和后台控制。

目前仅适配**小说书源**，不包含漫画、音频、视频及文件型书源。具体可用功能取决于书源与对应网站；兼容格式不代表内容已获授权或服务持续可用。

## 下载与更新

**当前版本：0.4.0。官方不再提供 0.4.0 之前版本的安装包，历史 `source.zip` 继续保留。**

[下载页面](https://git.3952039.xyz/#releases) · [GitHub 官方发布页](https://github.com/mikufoxxx/Wenku8_Flutter/releases/latest) · [本版完整说明](CHANGELOG.md)

| 设备 | 选择的安装包 |
| --- | --- |
| 常见 Android 手机、平板 | **ARM64 / arm64-v8a** |
| 32 位 ARM 设备 | ARMv7 / armeabi-v7a |
| x86_64 设备或模拟器 | x86_64 |

应用内可在 **我的 → 关于 → 检查更新** 获取后续版本。

### 从旧版升级

1. **先备份阅读记录，不要先卸载旧版。** 正式版沿用原安装标识与签名，可覆盖升级。
2. 原有书架、本地图书、分类、缓存、阅读进度和书签继续保留；已缓存内容仍可离线阅读。
3. 原内置来源不再提供在线内容。需要继续阅读未缓存章节时，先导入对应书源，再从旧书详情页选择 **关联书源**。

## 开始使用

**在线阅读**：打开 **我的 → 书源管理**，导入有权使用的书源，确认启用后到发现页浏览或搜索。

**本地阅读**：打开本地页面右上角 **＋**，选择文件、扫描文件夹或从网盘导入；开启合并书架后，导入入口位于书架右上角。

**专注阅读**：在设置中开启阅读器模式，或使用离线适配；支持简体中文、香港繁体和台湾繁体。

[阅读器与本地书库](docs/READER.md) · [自定义书源](docs/CUSTOM_SOURCES.md) · [搜索指南](docs/SEARCH.md)

## 使用声明与风险

**本项目明确反对并不支持任何侵权行为。** 纸间文库是通用阅读工具，不内置、托管或分发小说资源，不提供书源推荐、合集或订阅分发服务，也不提供绕过付费、账号权限、数字版权保护或其他访问限制的服务。

- 仅使用已获授权、属于公共领域或你依法有权使用的作品与服务。能够导入规则或拥有文件，不代表获得作品的复制、分享或传播授权。
- 第三方书源可能访问外部服务，搜索内容及填写的登录资料可能发送至其指定的网站。不要向不可信书源提供账号或个人信息。
- 妥善保存原始文件并定期备份；分享书源、备份或反馈问题前，请移除敏感信息。

完整说明见[使用与风险声明](docs/RESPONSIBLE_USE.md)，App 内也可从 **我的 → 关于** 查看。权利反馈请通过 [Issues](https://github.com/mikufoxxx/Wenku8_Flutter/issues) 提供具体信息，维护者将核查处理。

> **再次提醒：0.4.0 起为零内置书源版本；官方渠道停止提供 0.4.0 之前版本的安装包，历史源码归档保留。**

## 开发与贡献

欢迎反馈问题、提出建议或提交 Pull Request。请提供应用版本、Android 版本和复现步骤，不要公开上传账号、登录信息或未经授权的整本作品。

本项目使用 Flutter，优先支持 Android。[构建与签名](docs/RELEASING.md)包含本地构建和 GitHub Actions 使用方法；[书源兼容说明](docs/CUSTOM_SOURCES.md)列出当前支持范围。

## 致谢与许可

项目源自 [MewX/light-novel-library_Wenku8_Android](https://github.com/MewX/light-novel-library_Wenku8_Android)，感谢 MewX、Baby Pepper（SeraphRoy）、Jack Liu（aaassseee）及原项目贡献者。纸间文库由本项目维护者独立维护，不代表原平台或上游作者。

原项目 [GPL v2 或后续版本声明](LICENSE)保留，本 Flutter 组合版本按 [GPL v3](assets/licenses/GPL-3.0.txt) 分发。感谢 LegadoTeam / gedoor 及贡献者、Liquid Glass Easy、edge-tts 和其他开源项目。

完整来源、修改说明与第三方许可见 [NOTICE](NOTICE) 和 [第三方组件许可](docs/THIRD_PARTY.md)。应用代码的开源许可不授予第三方作品或服务的使用权。

---

[LINUX DO 社区](https://linux.do/)
