import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/services/notification_service.dart';
import 'package:shonenx/features/calendar/domain/models/calendar_entry.dart';
import 'package:shonenx/features/notifications/domain/models/notification_subscription.dart';
import 'package:shonenx/features/notifications/providers/notification_subscriptions_provider.dart';

/// Interactive live-updating countdown badge with 1-tap notification subscription toggle.
class AiringCountdownBadge extends ConsumerStatefulWidget {
  final CalendarEntry entry;
  final bool compact;

  const AiringCountdownBadge({
    super.key,
    required this.entry,
    this.compact = false,
  });

  @override
  ConsumerState<AiringCountdownBadge> createState() =>
      _AiringCountdownBadgeState();
}

class _AiringCountdownBadgeState extends ConsumerState<AiringCountdownBadge>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Update countdown every 30 seconds
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatCountdown(Duration diff) {
    if (diff.isNegative) return 'Live now';
    if (diff.inDays > 0) {
      final days = diff.inDays;
      final hours = diff.inHours % 24;
      return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    }
    if (diff.inHours > 0) {
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      return '${hours}h ${mins}m';
    }
    if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m';
    }
    return '< 1m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final airingAt = widget.entry.airingAt;
    final now = DateTime.now();
    final diff = airingAt != null ? airingAt.difference(now) : null;
    final isAired = widget.entry.isAired || (diff != null && diff.isNegative);
    final isImminent = diff != null && !diff.isNegative && diff.inHours < 2;

    // Check notification subscription status for this entry
    final subscriptions = ref.watch(notificationSubscriptionsProvider);
    final subKey = 'animeAiring_${widget.entry.mediaId}';
    final isSubscribed =
        subscriptions.containsKey(subKey) && subscriptions[subKey]!.isEnabled;

    final countdownText = diff != null ? _formatCountdown(diff) : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (countdownText.isNotEmpty)
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: isImminent ? _pulseAnimation.value : 1.0,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 4.5 : 6,
                    vertical: widget.compact ? 1.5 : 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: isAired
                        ? Colors.black.withValues(alpha: 0.6)
                        : (isImminent
                            ? cs.error.withValues(alpha: 0.9)
                            : cs.primary.withValues(alpha: 0.88)),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: isImminent
                        ? [
                            BoxShadow(
                              color: cs.error.withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isImminent) ...[
                        const Icon(
                          Icons.bolt_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                      ],
                      Text(
                        countdownText,
                        style: TextStyle(
                          fontSize: widget.compact ? 8.5 : 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: isAired ? Colors.white70 : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        if (!isAired) ...[
          const SizedBox(width: 4),
          InkWell(
            onTap: () async {
              HapticFeedback.lightImpact();
              final media = widget.entry.toUnifiedMedia();
              final notifier =
                  ref.read(notificationSubscriptionsProvider.notifier);

              await notifier.toggleSubscription(media);

              if (context.mounted) {
                final nowSubscribed = !isSubscribed;
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    content: Row(
                      children: [
                        Icon(
                          nowSubscribed
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_off_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            nowSubscribed
                                ? 'Alert scheduled for ${widget.entry.displayTitle}'
                                : 'Alerts cancelled for ${widget.entry.displayTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isSubscribed
                    ? cs.primary
                    : Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSubscribed
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: widget.compact ? 11 : 13,
                color: isSubscribed ? cs.onPrimary : Colors.white70,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
