import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_ui.dart';
import '../app_interactions.dart';
import 'app_updates.dart';
import 'release_policy.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const currentReleaseSummary = [
  '应用更名为纸间文库，支持导入阅读 App 3.0 的小说书源。',
  '保留原有书库、缓存、进度、书签与阅读功能，新增背景图和本地导入选项。',
  '改进搜索、分类、登录与插图显示，移除内置中文字库，减小安装包体积。',
];

const currentReleaseSections = [
  ReleaseSection('重要变更，请务必阅读', [
    zeroSourceNotice,
    '在线阅读需要自行导入可信、合法且有权使用的书源；本地阅读可继续直接使用。',
    retiredPackagesNotice,
  ]),
  ReleaseSection('应用更名与入口调整', [
    '应用更名为「纸间文库」，原有图标、奶白玻璃界面、立体书架和转场风格继续保留。',
    '「我的」中的原平台账号入口调整为「书源管理」；不再提供原内置平台的账号、榜单、出版分类及云端收藏入口。',
    '发现页右上角新增书源管理入口，左上角标识更换为 App 图标。',
    '书源管理的导入与导出操作集中在一行，分组可横向切换，减少向下翻找。',
    '发现、书架、本地均支持再次点击当前底部栏目平滑返回顶部；正常切换栏目仍保留浏览位置。',
  ]),
  ReleaseSection('自定义书源与兼容范围', [
    '支持导入阅读 App 3.0 的小说书源，包括常见 JSON 书源和脚本型小说书源。',
    '当前兼容小说搜索、发现分类、书籍详情、分卷目录、正文章节、封面与文中插图，以及账号登录、网页登录和验证码等验证流程。',
    '本版仅适配小说书源，暂不支持漫画、音频、视频及文件型书源。各项功能是否可用，取决于书源本身及对应网站的支持情况。',
    '可从文件、链接或粘贴内容导入，预览并勾选后再保存；支持编辑、启停、分组、排序、检查和导出。更新已有书源时保留启用状态。',
    '搜索可指定一个书源，或同时搜索全部启用的书源。兼容书源格式不代表应用附带书源，0.4.0 起所有书源均需用户自行导入。',
  ]),
  ReleaseSection('搜索、分类与登录改进', [
    '改进简体、繁体及港／台常见字形的搜索匹配，减少不相关结果。',
    '发现分类改为分组切换与多列选择，支持搜索分类。改进作者作品和标签书单的后续加载，书源提供对应入口时可继续浏览更多作品。',
    '书源卡片新增账号状态，区分未登录、会话已保存、登录已验证和登录失效等情况。',
    '修正网页登录后返回 App，登录状态未用于后续浏览的问题。登录页面支持系统账号与密码自动填充。',
    '对明确支持的书源，提供登录验证、云书架合并和手动签到。合并不会覆盖本机已有进度或书签。',
  ]),
  ReleaseSection('阅读器与本地导入', [
    '阅读设置「排版」新增自定义背景图，可选择、更换、移除并调整显示浓度。修正部分设备隐藏系统状态栏后顶部出现黑块的问题。',
    '本地及合并书架右上角「＋」新增「导入选项」，支持自定义目录识别和匹配预览。没有原始标题的章节默认显示为「未命名章节」，也可自行开启章节编号。',
    '修正部分 EPUB 插图前后缺少正文、普通首段被误删的问题。改进文中插图显示，无法加载的在线插图不再占据整页或留下大块空白，仍可从插图入口查看与重试。',
    '修正部分书籍的书名、作者、简介、标签和分卷识别问题。目录加载失败时保留已显示的书籍信息，重试不再让整个详情页重新开始。',
  ]),
  ReleaseSection('原有书库与记录保留', [
    '保留原有书架、本地图书、分类、缓存、阅读进度和书签，已缓存的旧书仍可离线阅读。',
    '旧在线书不再通过原内置来源加载。阅读未缓存章节前，请先导入对应书源，再到旧书详情页使用「关联书源」。停用或移除书源，不会同时删除书籍记录和已缓存正文。',
    '原有滚动、横排／竖排翻页、平板双页、书签、听书及本地导入功能继续保留。在线小说继续仅支持应用内缓存，不提供小说文件下载或导出。',
    '升级前建议先备份阅读记录，不要通过卸载旧版的方式进行升级。',
  ]),
  ReleaseSection('字体与使用体验', [
    '移除内置中文字库，默认使用系统字体，减小安装包体积。继续支持导入 TTF／OTF 字体，App 与阅读器可分别选择。',
    '原内置字体选项自动调整为系统字体，已导入字体及阅读记录保留。',
    '改进阅读器控件收放、长目录和多图片场景的处理，保留现有动效与模糊效果。',
  ]),
  ReleaseSection('使用声明与风险提示', [
    '纸间文库是通用阅读工具，不内置、托管或分发小说资源，不提供书源推荐、合集或订阅分发服务。',
    '本项目明确反对并不支持任何侵权行为，不提供绕过付费、账号权限、数字版权保护或其他访问限制的服务。',
    '请仅使用已获授权、属于公共领域或你依法有权使用的作品与服务。能够导入书源或拥有文件，不代表获得复制、分享或传播作品的授权。',
    '第三方书源可能访问外部服务，搜索内容及填写的登录资料可能发送至其指定的网站。不要向不可信书源提供账号或个人信息。',
    '书源兼容不代表内容已获授权，也不保证对应网站安全或持续可用。请妥善保存原始文件并定期备份，分享书源、备份或反馈问题前移除敏感信息。',
    '如发现项目公开材料涉及权利问题，请通过项目官方反馈渠道提供具体信息，维护者将核查处理。',
    zeroSourceNotice,
    retiredPackagesNotice,
  ]),
];

class CurrentReleaseCard extends StatelessWidget {
  const CurrentReleaseCard({super.key, this.updates});
  final AppUpdates? updates;
  @override
  Widget build(BuildContext context) {
    final service = updates;
    Widget card() => ContentPanel(
      key: const ValueKey('current-release-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArchiveSection(
            title: '本版更新',
            code:
                'RELEASE / ${service?.installed?.version ?? currentAppVersion}',
          ),
          const SizedBox(height: 12),
          const ReleasePolicyNotice(),
          const SizedBox(height: 14),
          for (final item in currentReleaseSummary)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppText(
                '· $item',
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
            ),
          const SizedBox(height: 6),
          GlassTextButton(
            key: const ValueKey('view-current-release-details'),
            onPressed: () =>
                showInstalledReleaseNotes(context, updates: service),
            child: const AppText('查看详细更新说明'),
          ),
        ],
      ),
    );
    return service == null
        ? card()
        : AnimatedBuilder(animation: service, builder: (_, _) => card());
  }
}

Future<bool> showInstalledReleaseNotes(
  BuildContext context, {
  AppUpdates? updates,
  bool automatic = false,
}) async {
  if (updates != null && updates.installed == null) {
    try {
      await updates.loadInstalled();
    } catch (_) {
      // Manual viewing remains available when platform metadata is unavailable.
    }
    if (!context.mounted) return false;
  }
  final installed = updates?.installed;
  final appearance = GlassAppearance.of(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  final completed =
      await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: !automatic,
        barrierLabel: '关闭更新说明',
        barrierColor: Colors.black.withValues(alpha: .16),
        transitionDuration: reduced ? Duration.zero : NovelMotion.enter,
        transitionBuilder: (context, animation, secondary, child) =>
            GlassOverlayTransition(
              animation: animation,
              kind: GlassOverlayKind.sheet,
              reduceMotion: reduced,
              child: child,
            ),
        pageBuilder: (context, _, _) => GlassAppearance(
          blur: appearance.blur,
          opacity: appearance.opacity,
          child: PopScope(
            canPop: !automatic,
            child: _ReleaseDetails(
              version: installed?.version ?? currentAppVersion,
              build: installed?.build ?? currentAppBuild,
            ),
          ),
        ),
      ) ==
      true;
  if (completed && installed != null && updates != null) {
    try {
      await updates.rememberReleaseNotes(installed);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '阅读状态未保存，下次打开可能再次显示');
    }
  }
  return completed;
}

class _ReleaseDetails extends StatefulWidget {
  const _ReleaseDetails({required this.version, required this.build});
  final String version;
  final int build;
  @override
  State<_ReleaseDetails> createState() => _ReleaseDetailsState();
}

class _ReleaseDetailsState extends State<_ReleaseDetails> {
  final _pages = PageController();
  final _sections = currentReleaseSections
      .where((s) => s.items.isNotEmpty)
      .toList(growable: false);
  int _page = 0;
  bool _moving = false;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _move(int page) async {
    if (_moving) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      setState(() => _moving = true);
      await _pages.animateToPage(
        page,
        duration: NovelMotion.enter,
        curve: NovelMotion.ease,
      );
      if (mounted) setState(() => _moving = false);
    }
  }

  Widget _navigation(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final previous = GlassTextButton(
        key: const ValueKey('release-details-previous'),
        onPressed: _page == 0 || _moving ? null : () => _move(_page - 1),
        child: const AppText('上一页'),
      );
      final next = GlassPillButton(
        key: const ValueKey('release-details-next'),
        label: _page == _sections.length - 1 ? '完成' : '下一页',
        icon: _page == _sections.length - 1
            ? CupertinoIcons.checkmark
            : CupertinoIcons.arrow_right,
        onPressed: _moving
            ? null
            : () {
                if (_page == _sections.length - 1) {
                  Navigator.pop(context, true);
                } else {
                  _move(_page + 1);
                }
              },
      );
      if (constraints.maxWidth <
          MediaQuery.textScalerOf(context).scale(14) * 8 + 120) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [previous, const SizedBox(height: 6), next],
        );
      }
      return Row(
        children: [
          Expanded(child: previous),
          const SizedBox(width: 12),
          Expanded(child: next),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
            child: GlassOverlaySurface(
              key: const ValueKey('installed-release-details'),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ArchiveCode(
                      'RELEASE / ${widget.version} · ${widget.build}',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: AppText(
                            '本版更新',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AppText(
                          '${_page + 1}/${_sections.length}',
                          key: const ValueKey('release-details-progress'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: PageView.builder(
                        key: const ValueKey('release-details-pages'),
                        controller: _pages,
                        itemCount: _sections.length,
                        onPageChanged: (page) => setState(() => _page = page),
                        itemBuilder: (context, index) => SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppText(
                                _sections[index].title,
                                key: ValueKey('release-section-$index'),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              for (final item in _sections[index].items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: AppText(
                                    '· $item',
                                    style: TextStyle(
                                      fontSize: index == 0 ? 16 : 14,
                                      height: 1.75,
                                      fontWeight:
                                          index == 0 ||
                                              item == zeroSourceNotice ||
                                              item == retiredPackagesNotice
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _navigation(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
