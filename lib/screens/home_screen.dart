import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/network_device.dart';
import '../state/router_controller.dart';
import '../widgets/device_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RouterController>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('WiFi — ${controller.host ?? ''}'),
          actions: [
            IconButton(
              tooltip: 'Rafraîchir',
              onPressed:
                  controller.isBusy ? null : () => controller.refresh(),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Se déconnecter',
              onPressed: () => controller.logout(),
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.wifi),
                text: 'Connectés (${controller.activeDevices.length})',
              ),
              Tab(
                icon: const Icon(Icons.block),
                text: 'Bloqués (${controller.blockedDevices.length})',
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            if (controller.isBusy) const LinearProgressIndicator(),
            if (controller.errorMessage != null)
              _ErrorBanner(message: controller.errorMessage!),
            Expanded(
              child: TabBarView(
                children: [
                  _DeviceList(
                    devices: controller.activeDevices,
                    emptyText:
                        'Aucun appareil détecté.\nTire vers le bas pour rafraîchir.',
                    onRefresh: controller.refresh,
                    controller: controller,
                  ),
                  _DeviceList(
                    devices: controller.blockedDevices,
                    emptyText: 'Aucun appareil bloqué.',
                    onRefresh: controller.refresh,
                    controller: controller,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.devices,
    required this.emptyText,
    required this.onRefresh,
    required this.controller,
  });

  final List<NetworkDevice> devices;
  final String emptyText;
  final Future<void> Function() onRefresh;
  final RouterController controller;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: devices.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Icon(Icons.devices_other,
                    size: 64, color: Theme.of(context).disabledColor),
                const SizedBox(height: 16),
                Text(emptyText, textAlign: TextAlign.center),
              ],
            )
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, i) {
                final d = devices[i];
                return DeviceTile(
                  device: d,
                  enabled: !controller.isBusy,
                  onToggleBlock: (block) =>
                      _confirmToggle(context, controller, d, block),
                );
              },
            ),
    );
  }

  Future<void> _confirmToggle(
    BuildContext context,
    RouterController controller,
    NetworkDevice device,
    bool block,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(block ? 'Bloquer cet appareil ?' : 'Débloquer ?'),
        content: Text(
          block
              ? '"${device.displayName}" perdra l\'accès à ton WiFi.'
              : '"${device.displayName}" retrouvera l\'accès à ton WiFi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(block ? 'Bloquer' : 'Débloquer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.setBlocked(device, block);
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.warning_amber),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
