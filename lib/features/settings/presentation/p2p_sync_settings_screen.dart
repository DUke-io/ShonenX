import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shonenx/features/settings/presentation/widgets/settings_ui_components.dart';
import 'package:shonenx/features/sync/presentation/widgets/device_pairing_dialog.dart';
import 'package:shonenx/features/sync/providers/p2p_sync_provider.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';

class P2PSyncSettingsScreen extends ConsumerStatefulWidget {
  const P2PSyncSettingsScreen({super.key});

  @override
  ConsumerState<P2PSyncSettingsScreen> createState() => _P2PSyncSettingsScreenState();
}

class _P2PSyncSettingsScreenState extends ConsumerState<P2PSyncSettingsScreen> {
  final TextEditingController _mnemonicInputController = TextEditingController();

  @override
  void dispose() {
    _mnemonicInputController.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  void _showRecoveryKeySheet(String mnemonic) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final words = mnemonic.split(' ');
        final cs = Theme.of(ctx).colorScheme;

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Your 12-Word Recovery Key',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Write down or securely save these 12 words. If you reinstall KuroX or switch devices, entering these words will restore all your data from the swarm.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(words.length, (index) {
                  return Chip(
                    avatar: CircleAvatar(
                      radius: 10,
                      backgroundColor: cs.primaryContainer,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(fontSize: 10, color: cs.onPrimaryContainer),
                      ),
                    ),
                    label: Text(
                      words[index],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: cs.surfaceContainerHighest,
                  );
                }),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy to Clipboard'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: mnemonic));
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recovery key copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSignInDialog() {
    _mnemonicInputController.clear();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Sign In to KuroX'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your 12-word recovery key to restore your watch history, favorites, and settings from the swarm.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _mnemonicInputController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'word1 word2 word3 ... word12',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (Platform.isAndroid || Platform.isIOS)
                OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan Pairing QR'),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final scanned = await showDialog<String>(
                      context: context,
                      builder: (_) => const ScanPairingQrDialog(),
                    );
                    if (scanned != null && mounted) {
                      _performSignIn(scanned);
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = _mnemonicInputController.text.trim();
                Navigator.of(ctx).pop();
                if (text.isNotEmpty) {
                  _performSignIn(text);
                }
              },
              child: const Text('Sign In & Restore'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performSignIn(String mnemonic) async {
    try {
      await ref.read(p2pSyncProvider.notifier).signInWithMnemonic(mnemonic);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in! Data successfully restored from swarm.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _performSignUp() async {
    try {
      final mnemonic = await ref.read(p2pSyncProvider.notifier).signUp();
      if (mounted) {
        _showRecoveryKeySheet(mnemonic);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign up failed: ${e.toString()}')),
        );
      }
    }
  }

  void _confirmDeleteSeederData() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete Seeder Data?'),
          content: const Text(
            'This will delete all cached peer blobs hosted on this device to free up storage.\n\nYour own personal account data, watch history, and favorites will NOT be affected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ref.read(p2pSyncProvider.notifier).clearSeederData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Seeder data deleted successfully.')),
                  );
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Sign Out?'),
          content: const Text(
            'Make sure you have saved your 12-word recovery key before signing out, or you will not be able to restore your data on this device later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ref.read(p2pSyncProvider.notifier).signOut();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed out.')),
                  );
                }
              },
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(p2pSyncProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final dateFormat = DateFormat('MMM d, y · h:mm a');
    final lastSyncText = syncState.lastSyncDate != null
        ? dateFormat.format(syncState.lastSyncDate!)
        : 'Never';

    return AppScaffold(
      title: 'P2P Device Sync',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // Account Status Section
          SettingsSection(
            title: 'Account & Identity',
            children: [
              if (syncState.isSignedIn) ...[
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Icon(Icons.person_rounded, color: cs.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'KuroX Account (Active Seeder)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    'Peer ID: ${syncState.identity?.peerId}',
                                    style: TextStyle(fontSize: 12, color: cs.outline),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.key_rounded, size: 18),
                                label: const Text('Recovery Key'),
                                onPressed: () {
                                  if (syncState.identity != null) {
                                    _showRecoveryKeySheet(syncState.identity!.mnemonic);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.qr_code_rounded, size: 18),
                                label: const Text('Pair Device'),
                                onPressed: () {
                                  if (syncState.identity != null) {
                                    showDialog(
                                      context: context,
                                      builder: (_) => ShowPairingQrDialog(
                                        mnemonic: syncState.identity!.mnemonic,
                                        peerId: syncState.identity!.peerId,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: cs.error),
                            icon: const Icon(Icons.logout_rounded, size: 16),
                            label: const Text('Sign Out'),
                            onPressed: _confirmSignOut,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Decentralized KuroX Cloud',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Keep your watch history, favorites, and settings safe across devices and app reinstalls without any central servers.',
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.person_add_rounded, size: 18),
                                label: const Text('Sign Up'),
                                onPressed: _performSignUp,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.login_rounded, size: 18),
                                label: const Text('Sign In'),
                                onPressed: _showSignInDialog,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Swarm & Sync Cadence Section
          SettingsSection(
            title: 'Swarm & Synchronization',
            children: [
              SettingsTile(
                title: 'Connected Peers',
                subtitle: '${syncState.activePeersCount} peers online in your swarm',
                leading: const Icon(Icons.hub_outlined),
              ),
              SettingsTile(
                title: 'Last Synchronized',
                subtitle: lastSyncText,
                leading: const Icon(Icons.schedule_outlined),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: FilledButton.tonalIcon(
                  icon: syncState.isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(syncState.isSyncing ? 'Syncing with Swarm...' : 'Sync Now'),
                  onPressed: syncState.isSignedIn && !syncState.isSyncing
                      ? () => ref.read(p2pSyncProvider.notifier).syncNow()
                      : null,
                ),
              ),
            ],
          ),

          // SEEDER DATA SECTION (User's specific requirement)
          SettingsSection(
            title: 'Seeder Data',
            subtitle: 'Encrypted peer fragments stored on this device to help other users',
            children: [
              Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.volunteer_activism_rounded, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Seeder Contribution',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                ),
                                Text(
                                  '${_formatBytes(syncState.seederDataSizeBytes)} cached · Helping ${syncState.seededPeersCount} peers',
                                  style: TextStyle(fontSize: 13, color: cs.outline),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'All hosted peer data is end-to-end encrypted with the owner\'s secret keys. Your device cannot read what is inside.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.error,
                            side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Delete Seeder Data'),
                          onPressed: syncState.seederDataSizeBytes > 0 || syncState.seededPeersCount > 0
                              ? _confirmDeleteSeederData
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
