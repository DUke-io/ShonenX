import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shonenx/features/player/syncplay/providers/syncplay_provider.dart';

class SyncPlaySheet extends ConsumerStatefulWidget {
  const SyncPlaySheet({super.key});

  @override
  ConsumerState<SyncPlaySheet> createState() => _SyncPlaySheetState();
}

class _SyncPlaySheetState extends ConsumerState<SyncPlaySheet> {
  late TextEditingController _codeController;
  late TextEditingController _usernameController;
  bool _isCreating = false;
  bool _isJoining = false;

  final List<String> _quickReactions = [
    '🔥',
    '😱',
    '😭',
    '🤣',
    '❤️',
    '⚡',
    '🎉',
    '🍿',
  ];

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _usernameController = TextEditingController(text: 'Watcher');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _hostParty() async {
    setState(() => _isCreating = true);
    try {
      final notifier = ref.read(syncPlayRoomProvider.notifier);
      final code = await notifier.createRoom(
        username: _usernameController.text.trim().isEmpty
            ? 'Host'
            : _usernameController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Watch party hosted! Room code: $code'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to host party: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinParty() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isJoining = true);
    try {
      final notifier = ref.read(syncPlayRoomProvider.notifier);
      final success = await notifier.joinByCode(
        code,
        username: _usernameController.text.trim().isEmpty
            ? 'Guest'
            : _usernameController.text.trim(),
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Joined Watch Party successfully!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to host. Check IP and port.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Join error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final room = ref.watch(syncPlayRoomProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.group_rounded, color: cs.primary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KuroX SyncPlay (Watch Together)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          room.isInRoom
                              ? (room.isHost
                                  ? 'Hosting Watch Party • ${room.peers.length} Watching'
                                  : 'Connected to Watch Party')
                              : 'Real-time multi-device playback synchronization',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (room.isInRoom)
                    IconButton(
                      tooltip: 'Leave Room',
                      icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                      onPressed: () async {
                        await ref.read(syncPlayRoomProvider.notifier).leaveRoom();
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: room.isInRoom
                  ? _buildActiveRoomView(context, room, cs, theme)
                  : _buildLobbyView(context, cs, theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRoomView(
    BuildContext context,
    dynamic room,
    ColorScheme cs,
    ThemeData theme,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: [
        // Room Code Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ROOM CODE / HOST ADDRESS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      room.roomCode,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Copy Room Code',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: room.roomCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Room code copied to clipboard!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Show QR Code',
                icon: const Icon(Icons.qr_code_rounded, size: 18),
                onPressed: () => _showQrModal(context, room.roomCode),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Quick Reactions bar
        Text(
          'Live Anime Reactions',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _quickReactions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final emoji = _quickReactions[index];
              return InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref.read(syncPlayRoomProvider.notifier).sendReaction(emoji);
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Peers List
        Text(
          'Watching Now (${room.peers.length})',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...room.peers.map((peer) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: peer.isHost ? cs.primary : cs.secondaryContainer,
              child: Icon(
                peer.isHost ? Icons.star_rounded : Icons.person_rounded,
                color: peer.isHost ? cs.onPrimary : cs.onSecondaryContainer,
                size: 18,
              ),
            ),
            title: Text(
              peer.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              peer.isHost ? 'Host' : 'Guest • Synced (±${peer.latencyMs}ms)',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 10, color: Colors.greenAccent),
                  SizedBox(width: 3),
                  Text(
                    'In Sync',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLobbyView(BuildContext context, ColorScheme cs, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: [
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Your Nickname',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isCreating ? null : _hostParty,
          icon: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_to_queue_rounded),
          label: Text(_isCreating ? 'Hosting...' : 'Host Watch Party'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR JOIN EXISTING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          decoration: const InputDecoration(
            labelText: 'Room Code or Host IP:Port',
            hintText: 'e.g. 192.168.1.15:8492',
            prefixIcon: Icon(Icons.sensors_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _isJoining ? null : _joinParty,
          icon: _isJoining
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_rounded),
          label: Text(_isJoining ? 'Connecting...' : 'Join Watch Party'),
        ),
      ],
    );
  }

  void _showQrModal(BuildContext context, String data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan to Join Watch Party'),
        content: SizedBox(
          width: 220,
          height: 220,
          child: Center(
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              size: 200.0,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
