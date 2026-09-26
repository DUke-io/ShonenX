import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/features/player/syncplay/domain/models/syncplay_message.dart';
import 'package:shonenx/features/player/syncplay/providers/syncplay_provider.dart';

class FloatingReactionsOverlay extends ConsumerStatefulWidget {
  const FloatingReactionsOverlay({super.key});

  @override
  ConsumerState<FloatingReactionsOverlay> createState() =>
      _FloatingReactionsOverlayState();
}

class _FloatingReactionsOverlayState
    extends ConsumerState<FloatingReactionsOverlay> {
  final List<SyncReaction> _activeReactions = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final service = ref.read(syncPlayServiceProvider);
    _sub = service.onReaction.listen((reaction) {
      if (mounted) {
        setState(() {
          _activeReactions.add(reaction);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _removeReaction(SyncReaction r) {
    if (mounted) {
      setState(() {
        _activeReactions.removeWhere((item) => item.id == r.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: _activeReactions.map((reaction) {
          return _FloatingEmojiItem(
            key: ValueKey(reaction.id),
            reaction: reaction,
            onComplete: () => _removeReaction(reaction),
          );
        }).toList(),
      ),
    );
  }
}

class _FloatingEmojiItem extends StatefulWidget {
  final SyncReaction reaction;
  final VoidCallback onComplete;

  const _FloatingEmojiItem({
    super.key,
    required this.reaction,
    required this.onComplete,
  });

  @override
  State<_FloatingEmojiItem> createState() => _FloatingEmojiItemState();
}

class _FloatingEmojiItemState extends State<_FloatingEmojiItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _translateAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _translateAnimation = Tween<double>(begin: 0.0, end: -280.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.2, end: 1.3), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 70),
    ]).animate(_controller);

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.65, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final leftPos = size.width * widget.reaction.horizontalPercent;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: leftPos,
          bottom: 90 + (-_translateAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.reaction.emoji,
                    style: const TextStyle(fontSize: 34),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.reaction.senderName,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
