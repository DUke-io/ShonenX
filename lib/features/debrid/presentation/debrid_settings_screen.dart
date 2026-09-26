import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shonenx/features/debrid/domain/models/debrid_config.dart';
import 'package:shonenx/features/debrid/providers/debrid_provider.dart';
import 'package:shonenx/features/settings/presentation/widgets/settings_ui_components.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';

class DebridSettingsScreen extends ConsumerStatefulWidget {
  const DebridSettingsScreen({super.key});

  @override
  ConsumerState<DebridSettingsScreen> createState() =>
      _DebridSettingsScreenState();
}

class _DebridSettingsScreenState extends ConsumerState<DebridSettingsScreen> {
  late TextEditingController _apiKeyController;
  bool _obscureKey = true;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(debridConfigProvider);
    _apiKeyController = TextEditingController(text: config.apiKey);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _verifyToken() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      _snack('Please enter an API key');
      return;
    }

    setState(() => _isTesting = true);
    await ref.read(debridConfigProvider.notifier).setApiKey(key);
    // Invalidate account info provider to trigger a fresh test
    ref.invalidate(debridAccountInfoProvider);

    try {
      final info = await ref.read(debridAccountInfoProvider.future);
      if (mounted) {
        if (info != null) {
          _snack(
            'Connected to ${info.username} (${info.type.toUpperCase()}${info.isPremium ? ' • ${info.daysRemaining} days left' : ''})',
          );
        } else {
          _snack('Failed to verify token. Please check your credentials.');
        }
      }
    } catch (e) {
      if (mounted) _snack('Verification failed: $e');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _openTokenPortal(DebridProvider provider) {
    String url = '';
    switch (provider) {
      case DebridProvider.realDebrid:
        url = 'https://real-debrid.com/apitoken';
        break;
      case DebridProvider.torbox:
        url = 'https://torbox.app/settings';
        break;
      case DebridProvider.allDebrid:
        url = 'https://alldebrid.com/apikeys/';
        break;
    }
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(debridConfigProvider);
    final accountAsync = ref.watch(debridAccountInfoProvider);
    final cs = Theme.of(context).colorScheme;

    return AppScaffold(
      title: 'Debrid & Torrent Streaming',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 50),
        children: [
          SettingsSection(
            title: 'General',
            children: [
              SettingsSwitchTile(
                icon: Icons.bolt_rounded,
                title: 'Enable Debrid Streaming',
                subtitle:
                    'Stream raw uncompressed 1080p/4K releases directly with zero transcoding',
                value: config.isEnabled,
                onChanged: (val) {
                  ref.read(debridConfigProvider.notifier).toggleEnabled(val);
                },
              ),
            ],
          ),
          if (config.isEnabled) ...[
            SettingsSection(
              title: 'Provider Selection',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: SegmentedButton<DebridProvider>(
                    segments: const [
                      ButtonSegment(
                        value: DebridProvider.realDebrid,
                        label: Text('Real-Debrid'),
                      ),
                      ButtonSegment(
                        value: DebridProvider.torbox,
                        label: Text('Torbox'),
                      ),
                      ButtonSegment(
                        value: DebridProvider.allDebrid,
                        label: Text('AllDebrid'),
                      ),
                    ],
                    selected: {config.provider},
                    onSelectionChanged: (set) {
                      ref
                          .read(debridConfigProvider.notifier)
                          .setProvider(set.first);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _apiKeyController,
                          obscureText: _obscureKey,
                          decoration: InputDecoration(
                            labelText: '${config.provider.displayName} API Key',
                            hintText: 'Paste secret API token...',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() => _obscureKey = !_obscureKey);
                              },
                            ),
                          ),
                          onSubmitted: (val) {
                            ref
                                .read(debridConfigProvider.notifier)
                                .setApiKey(val);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Get API Key',
                        onPressed: () => _openTokenPortal(config.provider),
                        icon: const Icon(Icons.open_in_new_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    onPressed: _isTesting ? null : _verifyToken,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(_isTesting ? 'Verifying...' : 'Validate Account'),
                  ),
                ),
                const SizedBox(height: 8),
                accountAsync.when(
                  data: (info) {
                    if (info == null) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            info.isPremium
                                ? Icons.verified_user_rounded
                                : Icons.info_outline_rounded,
                            color: cs.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  info.username,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  info.isPremium
                                      ? 'Premium Active • ${info.daysRemaining} days left'
                                      : 'Free Tier Account',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: info.isPremium
                                        ? cs.primary
                                        : cs.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
            SettingsSection(
              title: 'Scraper & Stream Quality',
              children: [
                ListTile(
                  title: const Text('Preferred Resolution'),
                  subtitle: Text(config.preferredResolution.label),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final res in PreferredResolution.values)
                              ListTile(
                                title: Text(res.label),
                                trailing: config.preferredResolution == res
                                    ? Icon(Icons.check, color: cs.primary)
                                    : null,
                                onTap: () {
                                  ref
                                      .read(debridConfigProvider.notifier)
                                      .setResolution(res);
                                  Navigator.pop(ctx);
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                SettingsSwitchTile(
                  icon: Icons.flash_on_rounded,
                  title: 'Instant Cache Only',
                  subtitle:
                      'Only stream torrents that are already 100% cached on Debrid for instant zero-buffering playback',
                  value: config.autoSelectCached,
                  onChanged: (val) {
                    ref.read(debridConfigProvider.notifier).saveConfig(
                          config.copyWith(autoSelectCached: val),
                        );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
