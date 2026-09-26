import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/features/debrid/domain/models/torrent_release.dart';
import 'package:shonenx/features/debrid/providers/debrid_provider.dart';
import 'package:shonenx/features/player/providers/player_controller.dart';

class DebridReleaseSheet extends ConsumerStatefulWidget {
  final PlayerController controller;

  const DebridReleaseSheet({super.key, required this.controller});

  @override
  ConsumerState<DebridReleaseSheet> createState() => _DebridReleaseSheetState();
}

class _DebridReleaseSheetState extends ConsumerState<DebridReleaseSheet> {
  bool _isLoading = true;
  List<TorrentRelease> _releases = [];
  String? _error;
  TorrentRelease? _loadingRelease;

  @override
  void initState() {
    super.initState();
    _loadReleases();
  }

  Future<void> _loadReleases() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final releases = await widget.controller.fetchDebridReleases();
      if (mounted) {
        setState(() {
          _releases = releases;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectRelease(TorrentRelease release) async {
    setState(() => _loadingRelease = release);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await widget.controller.loadDebridStream(release);
      if (mounted) {
        nav.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Streaming raw ${release.resolution} release via Debrid'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingRelease = null);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to load release: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = ref.watch(debridConfigProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                Icon(Icons.bolt_rounded, color: cs.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Debrid High-Bitrate Releases',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Uncompressed BDMV & 10-bit HEVC streams via ${config.provider.displayName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh releases',
                  onPressed: _isLoading ? null : _loadReleases,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Scraping AnimeTosho & Nyaa...'),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            'Error searching releases: $_error',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.error),
                          ),
                        ),
                      )
                    : _releases.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cloud_off_rounded,
                                    size: 48,
                                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text('No torrent releases found for this episode.'),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: _releases.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final release = _releases[index];
                              final isSelecting = _loadingRelease == release;

                              return ListTile(
                                enabled: !isSelecting,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                title: Text(
                                  release.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          release.resolution,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: cs.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                      if (release.isCachedOnDebrid)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: Colors.green.withValues(alpha: 0.6),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.bolt_rounded,
                                                size: 10,
                                                color: Colors.greenAccent,
                                              ),
                                              SizedBox(width: 2),
                                              Text(
                                                'Cached (0ms wait)',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.greenAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (release.isDualAudio)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Dual Audio',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.lightBlueAccent,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        '${release.formattedSize} • ${release.seeders} seeders • ${release.source}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: isSelecting
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2.5),
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.play_circle_fill_rounded),
                                        color: cs.primary,
                                        onPressed: () => _selectRelease(release),
                                      ),
                                onTap: isSelecting ? null : () => _selectRelease(release),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
