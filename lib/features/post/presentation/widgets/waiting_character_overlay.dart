import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// 投稿待機中に表示するキャラクターオーバーレイ
///
/// 3レイヤー構成:
/// 1. 背景演出（放射グラデーション + キラキラパーティクル）
/// 2. キャラクター（ゆらゆら浮遊 + タップでjellyアニメ + パーティクル）
/// 3. セリフ吹き出し（時間帯別 + 定期切り替え）
class WaitingCharacterOverlay extends StatefulWidget {
  static const String normalAssetPath = 'assets/onbord/taiki.webp';
  static const String happyAssetPath = 'assets/onbord/taiki_1.webp';

  final VoidCallback? onTap;

  const WaitingCharacterOverlay({super.key, this.onTap});

  @override
  State<WaitingCharacterOverlay> createState() =>
      _WaitingCharacterOverlayState();
}

class _WaitingCharacterOverlayState extends State<WaitingCharacterOverlay>
    with TickerProviderStateMixin {
  // ── キャラクター状態 ──
  static const Duration _swapDelay = Duration(seconds: 6);
  bool _isHappy = false;
  int _jellyTick = 0;
  Timer? _swapTimer;

  // ── 浮遊アニメーション ──
  late final AnimationController _floatController;
  late final Animation<double> _floatOffset;

  // ── jellyアニメーション ──
  late final AnimationController _jellyController;
  late final Animation<double> _scaleX;
  late final Animation<double> _scaleY;
  int _lastJellyTick = 0;

  // ── セレブレートグロー ──
  late final AnimationController _celebrateController;

  // ── タップパーティクル ──
  final List<_TapParticleGroup> _tapParticles = [];

  // ── セリフ ──
  static const Duration _speechInterval = Duration(seconds: 6);
  static const Duration _speechInitialDelay = Duration(milliseconds: 500);
  Timer? _speechTimer;
  String _currentSpeech = '';
  bool _speechVisible = false;
  late List<String> _speechPool;
  int _speechIndex = 0;

  // ── フェードイン ──
  bool _overlayVisible = false;

  @override
  void initState() {
    super.initState();

    // 浮遊アニメーション（上下にゆっくり）
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _floatOffset = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    // セレブレートグロー（フェードイン→フェードアウト）
    _celebrateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // jellyアニメーション
    _jellyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleX = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.14,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.14,
          end: 0.93,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.93,
          end: 1.05,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.05,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
    ]).animate(_jellyController);
    _scaleY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.90,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.90,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.12,
          end: 0.96,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.96,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
    ]).animate(_jellyController);

    // セリフプール構築
    _speechPool = _buildSpeechPool();

    // キャラクター切り替えタイマー
    _swapTimer = Timer(_swapDelay, _triggerCelebrate);

    // フェードインと初回セリフ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _overlayVisible = true);
    });
    _speechTimer = Timer(_speechInitialDelay, _showNextSpeech);
  }

  @override
  void dispose() {
    _swapTimer?.cancel();
    _speechTimer?.cancel();
    _floatController.dispose();
    _jellyController.dispose();
    _celebrateController.dispose();
    for (final group in _tapParticles) {
      group.controller.dispose();
    }
    super.dispose();
  }

  // ── セリフ ──

  static const String _firstSpeech = '投稿完了まで少し待っててね！';

  static const List<String> _commonSpeeches = [
    '今日はどんな気分かな？',
    '私をタップしてね😊',
    'がんばってるの、ちゃんと見てるよ✨',
    'あなたの投稿、楽しみだな〜！',
  ];

  static const List<String> _morningSpeeches = [
    'おはよう！今日はどんな日になるかな？',
    'おはよう！今日がいい日になりますように😊',
  ];

  static const List<String> _daytimeSpeeches = [
    'こんにちは！お昼ごはんは食べたかな？',
    '午後もファイトだよ〜！',
  ];

  static const List<String> _nightSpeeches = [
    '今日もお疲れ様💕',
    'とても頑張ったね！',
    '今日はどんな日だったかな？',
    'ゆっくり休んでね🌙',
    '今日も投稿ありがとう💕',
  ];

  List<String> _buildSpeechPool() {
    final hour = DateTime.now().hour;
    List<String> timeSpeeches;
    if (hour >= 5 && hour < 11) {
      timeSpeeches = _morningSpeeches;
    } else if (hour >= 11 && hour < 17) {
      timeSpeeches = _daytimeSpeeches;
    } else {
      timeSpeeches = _nightSpeeches;
    }
    final pool = [..._commonSpeeches, ...timeSpeeches];
    pool.shuffle(Random());
    return pool;
  }

  void _showNextSpeech() {
    if (!mounted) return;
    setState(() {
      if (_speechIndex == 0) {
        // 初回は固定セリフ
        _currentSpeech = _firstSpeech;
      } else {
        final poolIndex = (_speechIndex - 1) % _speechPool.length;
        _currentSpeech = _speechPool[poolIndex];
      }
      _speechVisible = true;
      _speechIndex++;
    });
    _speechTimer?.cancel();
    _speechTimer = Timer(_speechInterval, () {
      if (!mounted) return;
      setState(() => _speechVisible = false);
      // フェードアウト完了後に次を表示
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _showNextSpeech();
      });
    });
  }

  // ── キャラクター ──

  void _triggerCelebrate() {
    if (!mounted) return;
    setState(() => _isHappy = true);
    // グローをフェードイン→自動フェードアウト
    _celebrateController.forward(from: 0).then((_) {
      if (mounted) _celebrateController.reverse();
    });
  }

  void _onTap() {
    if (!mounted) return;
    widget.onTap?.call();

    // jellyアニメーション
    setState(() => _jellyTick += 1);
    if (_jellyTick != _lastJellyTick) {
      _lastJellyTick = _jellyTick;
      _jellyController.forward(from: 0);
    }

    // パーティクル発生
    _spawnTapParticles();
  }

  // ── タップパーティクル ──

  static const List<String> _particleEmojis = ['❤️', '⭐', '♪', '✨', '💕'];

  void _spawnTapParticles() {
    final rng = Random();
    final count = 8 + rng.nextInt(5); // 8〜12個
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    final particles = List.generate(count, (_) {
      final angle = rng.nextDouble() * 2 * pi;
      final speed = 60 + rng.nextDouble() * 80; // 60-140px
      final emoji = _particleEmojis[rng.nextInt(_particleEmojis.length)];
      final size = 16.0 + rng.nextDouble() * 12; // 16-28
      return _TapParticle(angle: angle, speed: speed, emoji: emoji, size: size);
    });

    final group = _TapParticleGroup(
      controller: controller,
      particles: particles,
    );

    setState(() => _tapParticles.add(group));

    controller.forward().then((_) {
      if (mounted) {
        controller.dispose();
        setState(() => _tapParticles.remove(group));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _overlayVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Layer 1: 背景
            Positioned.fill(
              child: CustomPaint(
                painter: _SparkleBackgroundPainter(animation: _floatController),
              ),
            ),

            // Layer 2+3: キャラクター、パーティクル、吹き出し
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // セリフ吹き出し
                  AnimatedOpacity(
                    opacity: _speechVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 400),
                    child: _SpeechBubble(text: _currentSpeech),
                  ),
                  const SizedBox(height: 2),

                  // キャラクター + パーティクル
                  GestureDetector(
                    onTap: _onTap,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _floatController,
                        _jellyController,
                        _celebrateController,
                      ]),
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _floatOffset.value),
                          child: _buildCharacterWithParticles(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacterWithParticles() {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // タップパーティクル
          for (final group in _tapParticles)
            AnimatedBuilder(
              animation: group.controller,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(260, 260),
                  painter: _TapParticlePainter(
                    particles: group.particles,
                    progress: group.controller.value,
                  ),
                );
              },
            ),

          // キャラクター
          Builder(
            builder: (context) {
              final glow = _celebrateController.value;
              final glowScale = 1.0 + glow * 0.16; // 最大1.16倍
              return Transform.scale(
                scale: glowScale,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: glow > 0.01
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(
                                alpha: 0.50 * glow,
                              ),
                              blurRadius: 48 * glow,
                              spreadRadius: 12 * glow,
                            ),
                            BoxShadow(
                              color: const Color(
                                0xFFFFD54F,
                              ).withValues(alpha: 0.40 * glow),
                              blurRadius: 70 * glow,
                              spreadRadius: 16 * glow,
                            ),
                          ]
                        : null,
                  ),
                  child: Transform.scale(
                    alignment: Alignment.center,
                    scaleX: _scaleX.value,
                    scaleY: _scaleY.value,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 620),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: Image.asset(
                        _isHappy
                            ? WaitingCharacterOverlay.happyAssetPath
                            : WaitingCharacterOverlay.normalAssetPath,
                        key: ValueKey<bool>(_isHappy),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── セリフ吹き出し ──

class _SpeechBubble extends StatelessWidget {
  final String text;
  const _SpeechBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 吹き出し本体
        Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ),
        // しっぽ（三角）
        CustomPaint(size: const Size(20, 10), painter: _BubbleTailPainter()),
      ],
    );
  }
}

/// 吹き出しの下向き三角しっぽ
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    // 塗りつぶし
    canvas.drawPath(path, Paint()..color = Colors.white);

    // 枠線（左辺と右辺のみ）
    final borderPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(
      borderPath,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 背景キラキラパーティクル ──

class _SparkleBackgroundPainter extends CustomPainter {
  _SparkleBackgroundPainter({required this.animation})
    : super(repaint: animation);

  final Animation<double> animation;

  static const int _sparkleCount = 14;

  @override
  void paint(Canvas canvas, Size size) {
    // 背景グラデーション
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [
          AppColors.primary.withValues(alpha: 0.12),
          AppColors.secondary.withValues(alpha: 0.08),
          Colors.black.withValues(alpha: 0.30),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // キラキラ
    final rng = Random(42); // seed固定でフレーム間で一貫した位置
    final t = animation.value;

    for (int i = 0; i < _sparkleCount; i++) {
      final baseX = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.3 + rng.nextDouble() * 0.7;
      final phase = rng.nextDouble() * 2 * pi;

      // ゆっくり上昇 + 左右にゆれ
      final y = (baseY - t * speed * 120) % size.height;
      final x = baseX + sin(t * 2 * pi + phase) * 15;

      // 明滅
      final alpha = (0.3 + 0.7 * ((sin(t * 2 * pi * speed + phase) + 1) / 2));
      final radius = 1.5 + rng.nextDouble() * 2.0;

      final colors = [
        Colors.white,
        const Color(0xFFFFD1DC), // 淡いピンク
        const Color(0xFFFFECB3), // 淡いゴールド
      ];
      final color = colors[i % colors.length].withValues(alpha: alpha);

      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparkleBackgroundPainter oldDelegate) => true;
}

// ── タップパーティクルデータ ──

class _TapParticle {
  final double angle;
  final double speed;
  final String emoji;
  final double size;
  _TapParticle({
    required this.angle,
    required this.speed,
    required this.emoji,
    required this.size,
  });
}

class _TapParticleGroup {
  final AnimationController controller;
  final List<_TapParticle> particles;
  _TapParticleGroup({required this.controller, required this.particles});
}

// ── タップパーティクル描画 ──

class _TapParticlePainter extends CustomPainter {
  final List<_TapParticle> particles;
  final double progress;
  _TapParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final opacity = (1.0 - progress).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    for (final p in particles) {
      // Curved progress for natural deceleration
      final curved = Curves.easeOut.transform(progress);
      final dx = cos(p.angle) * p.speed * curved;
      final dy =
          sin(p.angle) * p.speed * curved - 20 * curved; // slight upward bias
      final pos = center + Offset(dx, dy);

      final textPainter = TextPainter(
        text: TextSpan(
          text: p.emoji,
          style: TextStyle(fontSize: p.size * opacity),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        pos - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TapParticlePainter oldDelegate) =>
      progress != oldDelegate.progress;
}
