/// 局域网同步页的 App 扫码与安装确认动作。
///
/// 保持弹窗上下文属于页面；传输和安装状态仍由两个应用控制器持有。
part of 'lan_sync_page.dart';

extension _LanSyncAppTransferActions on _LanSyncPageState {
  Future<void> _showAppTransferSheet() async {
    unawaited(ref.read(appTransferControllerProvider.notifier).startSending());
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final appState = ref.watch(appTransferControllerProvider);
          return LanSyncSheetFrame(
            title: '发送 App',
            description: '生成二维码后，对方使用“扫码连接 / 接收”即可继续。',
            closeLabel: appState.active ? '取消 App 传输' : '关闭',
            onClose: () {
              if (appState.active) unawaited(ref.read(appTransferControllerProvider.notifier).cancel());
              Navigator.of(sheetContext).pop();
            },
            footer: appState.phase == AppTransferPhase.completed || appState.phase == AppTransferPhase.failed
                ? FilledButton(
                    key: const Key('app-transfer-finish'),
                    onPressed: () {
                      unawaited(ref.read(appTransferControllerProvider.notifier).reset());
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('完成'),
                  )
                : null,
            child: AppTransferPanel(
              state: appState,
              showActions: false,
              onScanQr: null,
              onInstall: (force) => unawaited(ref.read(appTransferControllerProvider.notifier).install(force: force)),
              onCancel: () {
                unawaited(ref.read(appTransferControllerProvider.notifier).cancel());
                Navigator.of(sheetContext).pop();
              },
              onReset: () {
                unawaited(ref.read(appTransferControllerProvider.notifier).reset());
                Navigator.of(sheetContext).pop();
              },
            ),
          );
        },
      ),
    );
    if (mounted && ref.read(appTransferControllerProvider).active) await ref.read(appTransferControllerProvider.notifier).cancel();
  }

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

  Future<void> _confirmPairedAppUpdate(String deviceId, bool force) async {
    final deviceState = ref.read(deviceSyncControllerProvider);
    final offer = deviceState.appOffersByDeviceId[deviceId];
    final local = deviceState.localAppVersion;
    if (offer == null || local == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(force ? '强制安装此版本？' : '从在线设备升级 App？'),
        content: AppVersionComparisonCard(local: local, remote: offer.version, pairingCode: null),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            key: const Key('paired-app-update-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(force ? '强制安装' : '升级'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await ref.read(deviceSyncControllerProvider.notifier).installAppFrom(deviceId, force: force);
    }
  }
}
