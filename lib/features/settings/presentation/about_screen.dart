import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shonenx/core/network/http_client.dart';
import 'package:shonenx/core/router/app_navigator.dart';
import 'package:shonenx/features/settings/presentation/widgets/settings_ui_components.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';
import 'package:shonenx/shared/widgets/svg_icon.dart';
import 'package:url_launcher/url_launcher.dart';

class GithubContributor {
  final String login;
  final String avatarUrl;
  final String htmlUrl;
  final int contributions;

  const GithubContributor({
    required this.login,
    required this.avatarUrl,
    required this.htmlUrl,
    required this.contributions,
  });

  factory GithubContributor.fromJson(Map<String, dynamic> json) {
    return GithubContributor(
      login: json['login'] as String? ?? 'Unknown',
      avatarUrl: json['avatar_url'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      contributions: json['contributions'] as int? ?? 0,
    );
  }
}

final githubContributorsProvider = FutureProvider<List<GithubContributor>>((
  ref,
) async {
  try {
    final response = await HTTP().get(
      'https://api.github.com/repos/Zcross091/KuroX/contributors',
    );

    if (response.statusCode != 200) {
      return [];
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .whereType<Map<String, dynamic>>()
        .map(GithubContributor.fromJson)
        .toList();
  } catch (_) {
    return [];
  }
});

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final packageInfo = ref.watch(_packageInfoProvider);
    final contributors = ref.watch(githubContributorsProvider);

    return AppScaffold(
      title: 'About',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 50),
        children: [
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'KuroX',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              packageInfo.when(
                data: (info) => Text(
                  'Version ${info.version}+${info.buildNumber}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                loading: () => Text(
                  'Version ...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                error: (_, __) => Text(
                  'Version unknown',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          SettingsSection(
            title: 'Links',
            children: [
              SettingsActionTile(
                icon: Icons.system_update_outlined,
                title: 'Check for Updates',
                subtitle: 'Update settings and pre-release options',
                onTap: () => context.pushSettingsUpdates(),
              ),
              SettingsActionTile(
                icon: Icons.code_rounded,
                title: 'GitHub',
                subtitle: 'Source code and releases',
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/Zcross091/KuroX'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              SettingsActionTile(
                icon: Icons.bug_report_rounded,
                title: 'Report an Issue',
                subtitle: 'Found a bug? Let us know',
                onTap: () => launchUrl(
                  Uri.parse(
                    'https://github.com/Zcross091/KuroX/issues',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),

          SettingsSection(
            title: 'Information',
            children: [
              SettingsActionTile(
                icon: Icons.person_rounded,
                title: 'Lead Developer',
                subtitle: 'Zcross091',
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/Zcross091'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Contributors',
            children: [
              contributors.when(
                loading: () => const ListTile(
                  leading: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Loading contributors...'),
                ),
                error: (_, __) => const ListTile(
                  leading: Icon(Icons.error_outline),
                  title: Text('Failed to load contributors'),
                ),
                data: (contributors) {
                  final sorted = [...contributors];

                  const pinnedUsers = ['Zcross091'];

                  sorted.sort((a, b) {
                    final aIndex = pinnedUsers.indexOf(a.login);
                    final bIndex = pinnedUsers.indexOf(b.login);

                    if (aIndex != -1 && bIndex != -1) {
                      return aIndex.compareTo(bIndex);
                    }
                    if (aIndex != -1) return -1;
                    if (bIndex != -1) return 1;

                    return b.contributions.compareTo(a.contributions);
                  });

                  String roleFor(GithubContributor c) {
                    switch (c.login) {
                      case 'Zcross091':
                        return 'Lead Maintainer • KuroX Creator';
                      default:
                        return '${c.contributions} contributions';
                    }
                  }

                  return Column(
                    children: [
                      SettingsActionTile(
                        leading: const CircleAvatar(
                          backgroundImage: NetworkImage(
                            'https://github.com/Zcross091.png',
                          ),
                        ),
                        title: 'Zcross091',
                        subtitle: 'Lead Maintainer • KuroX Creator',
                        onTap: () => launchUrl(
                          Uri.parse('https://github.com/Zcross091'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),

                      ...sorted.take(10).map((contributor) {
                        return SettingsActionTile(
                          leading: buildAvatar(
                            contributor.login,
                            contributor.avatarUrl,
                            cs,
                          ),
                          title: contributor.login,
                          subtitle: roleFor(contributor),
                          onTap: () => launchUrl(
                            Uri.parse(contributor.htmlUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildAvatar(String login, String avatarUrl, ColorScheme cs) {
    Color? borderColor;

    switch (login) {
      case 'Zcross091':
        borderColor = cs.primary;
        break;

      case 'Darkx-Dev':
        borderColor = cs.secondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(
                color: borderColor,
                width: 3,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
      child: CircleAvatar(backgroundImage: NetworkImage(avatarUrl)),
    );
  }
}
