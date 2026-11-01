import 'package:flutter/material.dart';
import '../app_ui.dart';

const zeroSourceNotice = '自 0.4.0 起，纸间文库为零内置书源版本，不附带任何书源、书源合集或推荐订阅。';
const retiredPackagesNotice =
    '即日起，官方渠道不再提供 0.4.0 之前任何版本的安装包，包括历史正式版、测试版及预览版，不再提供旧版下载或补发；历史源码归档保留。';

class ReleasePolicyNotice extends StatelessWidget {
  const ReleasePolicyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('release-policy-notice'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.onSurface.withValues(alpha: .24)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText(
              '重要变更',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 7),
            AppText(
              '0.4.0 起 · 零内置书源',
              style: TextStyle(
                fontSize: 17,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            AppText(
              '停止提供 0.4.0 之前版本的安装包',
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
