import 'package:flutter/material.dart';

import '../models/network_device.dart';

/// Ligne affichant un appareil avec un bouton bloquer/débloquer.
class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.device,
    required this.onToggleBlock,
    this.enabled = true,
  });

  final NetworkDevice device;
  final ValueChanged<bool> onToggleBlock;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final blocked = device.isBlocked;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: blocked
              ? scheme.errorContainer
              : (device.isOnline ? scheme.primaryContainer : scheme.surfaceContainerHighest),
          child: Icon(
            blocked
                ? Icons.block
                : (device.isOnline ? Icons.devices : Icons.devices_other),
            color: blocked ? scheme.error : scheme.primary,
          ),
        ),
        title: Text(
          device.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (device.ip != null) Text('IP : ${device.ip}'),
            Text('MAC : ${device.mac}',
                style: Theme.of(context).textTheme.bodySmall),
            if (device.connectionType != null)
              Text(device.connectionType!,
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        isThreeLine: true,
        trailing: blocked
            ? OutlinedButton.icon(
                onPressed: enabled ? () => onToggleBlock(false) : null,
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Débloquer'),
              )
            : FilledButton.tonalIcon(
                onPressed: enabled ? () => onToggleBlock(true) : null,
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Bloquer'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.error,
                ),
              ),
      ),
    );
  }
}
