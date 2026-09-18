/// 局域网同步页的 App 扫码与安装确认动作。
///
/// 保持弹窗上下文属于页面；传输和安装状态仍由两个应用控制器持有。
part of 'lan_sync_page.dart';

extension _LanSyncAppTransferActions on _LanSyncPageState {
  Future<void> _connectScannedAppOffer(AppTransferConnectionOffer offer) async {
    final notifier = ref.read(appTransferControllerProvider.notifier);
    await notifier.connectOffer(offer);
    if (mounted && ref.read(appTransferControllerProvider).phase == AppTransferPhase.ready) {
      await _showTemporaryAppUpdatePrompt();
    }
  }

  Future<void> _showTemporaryAppUpdatePrompt() async {
    final appState = ref.read(appTransferControllerProvider);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appState.remoteIsUpgrade ? '发现可升级版本' : '安装此 App 版本？'),
        content: AppVersionComparisonCard(local: appState.localVersion, remote: appState.offeredVersion, pairingCode: appState.pairingCode),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('暂不安装')),
          FilledButton(
            key: const Key('app-transfer-dialog-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(appState.remoteIsUpgrade ? '升级' : '强制安装'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await ref.read(appTransferControllerProvider.notifier).install(force: !appState.remoteIsUpgrade);
    }
  }
}
