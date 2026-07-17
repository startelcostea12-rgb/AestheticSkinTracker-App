// lib/screens/ai_nurse_chat_screen.dart
//
// AI Nurse Chat — a focused, premium chat interface that lets the user
// ask general wellness questions about their Skin AI Analysis results.
//
// Key design decisions:
//   • Strong, repeated non-diagnostic disclaimers (banner + every response).
//   • Pre-seeded context messages so the chat feels meaningful immediately.
//   • Suggested prompt chips above the input so users know what to ask.
//   • Placeholder response logic; swap _sendMessage() body for a real API
//     call (e.g. OpenAI / Gemini) when the backend is ready.
//   • All styling mirrors the rest of the app's clinical / premium palette.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';

// ─── Public entry-point ───────────────────────────────────────────────────────

class AiNurseChatScreen extends StatefulWidget {
  /// The decoded backend payload from Deep Analysis, forwarded as context so
  /// that the AI Nurse can reference headline findings. May be null when
  /// opened standalone.
  final Map<String, dynamic>? analysisResult;

  const AiNurseChatScreen({super.key, this.analysisResult});

  @override
  State<AiNurseChatScreen> createState() => _AiNurseChatScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _AiNurseChatScreenState extends State<AiNurseChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<_ChatMessage> _messages = [];
  bool _sending = false;

  // Suggestions rotate based on whether an analysis result was passed in.
  late final List<String> _suggestions;

  bool get _hasUserMessage => _messages.any((m) => m.role == _Role.user);

  @override
  void initState() {
    super.initState();
    _suggestions = _buildSuggestions();
    _seedWelcome();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<String> _buildSuggestions() {
    final hasResult = widget.analysisResult != null;
    return [
      if (hasResult) 'What do my results mean in plain language?',
      'What ingredients are generally good for acne-prone skin?',
      'What questions should I ask my dermatologist?',
      'What can texture changes mean in a photo?',
      'What procedures are commonly discussed for acne marks?',
      if (hasResult) 'What lifestyle factors can affect skin redness?',
      'How often should I take photos to track my skin?',
    ];
  }

  void _seedWelcome() {
    final hasResult = widget.analysisResult != null;
    final headline =
        widget.analysisResult?['headline']?.toString() ??
        widget.analysisResult?['summary']?.toString();

    _messages.add(
      _ChatMessage(
        role: _Role.nurse,
        text:
            'Hi! I\'m AI Nurse — your general skin wellness guide. '
            '${hasResult ? 'I can see you just ran a photo analysis${headline != null ? ' ("$headline")' : ''}, so feel free to ask me about your results. ' : ''}'
            'I\'m here to explain terms, share general information, and help you prepare good questions for your dermatologist.\n\n'
            'Just a reminder: I\'m not a licensed healthcare professional, so everything I share is for educational purposes only.',
        isDisclaimer: false,
      ),
    );
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(role: _Role.user, text: trimmed));
      _sending = true;
    });
    _input.clear();
    _scrollToBottom();

    // TODO: Call real AI Nurse backend.
    // Replace this placeholder block with an API call, e.g.:
    //
    //   final response = await AiNurseService.chat(
    //     systemPrompt: aiSkinAdvisorSystemPrompt,
    //     userPrompt: buildAiSkinAdvisorUserPrompt(...),
    //     message: trimmed,
    //     context: widget.analysisResult,
    //   );
    //   final reply = response['reply'] ?? 'I\'m not sure — please ask your dermatologist.';
    //
    await Future.delayed(const Duration(milliseconds: 900));
    final reply = _placeholderReply(trimmed);

    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(
          role: _Role.nurse,
          text: reply,
          disclaimer:
              'This is general information only, not medical advice or a diagnosis.',
        ),
      );
      _sending = false;
    });
    _scrollToBottom(delayed: true);
  }

  String _placeholderReply(String question) {
    final q = question.toLowerCase();
    if (q.contains('redness') ||
        q.contains('erythema') ||
        q.contains('rosacea')) {
      return 'Facial redness can have many causes — sun exposure, sensitivity, '
          'rosacea, or post-inflammatory changes. A dermatologist can distinguish '
          'between these with an in-person evaluation. In the meantime, broad-spectrum '
          'SPF and gentle, fragrance-free products are broadly recommended for '
          'reactive skin.';
    }
    if (q.contains('acne') ||
        q.contains('breakout') ||
        q.contains('papule') ||
        q.contains('pustule') ||
        q.contains('pore')) {
      return 'Acne involves a mix of excess sebum, clogged pores, and bacterial '
          'activity. Ingredients commonly discussed in the literature include '
          'niacinamide (pore appearance), benzoyl peroxide (antibacterial), '
          'salicylic acid (exfoliation), and retinoids (cell turnover). '
          'A dermatologist can advise on the right combination and strength for you.';
    }
    if (q.contains('ingredient') ||
        q.contains('retinol') ||
        q.contains('vitamin c') ||
        q.contains('niacinamide') ||
        q.contains('sunscreen') ||
        q.contains('spf')) {
      return 'Great question! Common evidence-based skincare actives include '
          'retinoids (cell turnover), vitamin C (antioxidant, brightening), '
          'niacinamide (barrier support, redness), and broad-spectrum SPF '
          '(photo-ageing prevention). Always patch-test new actives and introduce '
          'them one at a time. Your dermatologist can personalise a routine '
          'for your specific skin type.';
    }
    if (q.contains('dermatologist') ||
        q.contains('doctor') ||
        q.contains('ask') ||
        q.contains('question')) {
      return 'Great idea to prepare! Some useful questions to bring: '
          '"Is this finding something I should monitor?", '
          '"What treatment options exist for this?", '
          '"Are there any prescription options that might help?", and '
          '"What should I avoid aggravating this condition?". '
          'Writing them down beforehand helps you get the most from your appointment.';
    }
    if (q.contains('scar') ||
        q.contains('pigment') ||
        q.contains('dark spot') ||
        q.contains('mark') ||
        q.contains('hyperpigmentation')) {
      return 'Post-inflammatory hyperpigmentation (dark marks left after breakouts) '
          'and scarring are different things — PIH often fades over months with '
          'proper sun protection, while atrophic scars (indentations) are structural. '
          'Ingredients like azelaic acid, tranexamic acid, and vitamin C are often '
          'discussed for pigmentation. A dermatologist can confirm which type you '
          'have and recommend the most appropriate approach.';
    }
    if (q.contains('texture') ||
        q.contains('rough') ||
        q.contains('bumpy') ||
        q.contains('pores') ||
        q.contains('uneven')) {
      return 'Texture changes in a photo can reflect many things, such as clogged '
          'pores, post-breakout marks, dryness, irritation, lighting, or natural '
          'skin variation. General skin-supportive basics include gentle cleansing, '
          'daily sunscreen, moisturiser, and introducing active ingredients slowly. '
          'A dermatologist can tell whether texture is acne-related, scarring, '
          'irritation, or something else.';
    }
    if (q.contains('procedure') ||
        q.contains('laser') ||
        q.contains('peel') ||
        q.contains('microneedling') ||
        q.contains('ipl') ||
        q.contains('treatment')) {
      return 'Procedures commonly discussed for cosmetic skin concerns include '
          'chemical peels, microneedling, IPL, vascular lasers, and resurfacing '
          'lasers. Suitability depends on skin tone, medical history, current '
          'medications, scar type, pigmentation risk, and in-person assessment. '
          'Please treat this as general education and review options with a '
          'qualified dermatologist or licensed clinician.';
    }
    if (q.contains('photo') ||
        q.contains('track') ||
        q.contains('scan') ||
        q.contains('often') ||
        q.contains('frequency')) {
      return 'For skin tracking, consistency matters more than frequency. '
          'Taking a photo every 2–4 weeks in the same lighting, same angle, '
          'and without makeup gives you the most comparable series. '
          'Weekly photos are fine too — just aim for the same conditions each time.';
    }
    // Generic fallback
    return 'That\'s a thoughtful question. While I can share general information, '
        'the most reliable answer will come from a dermatologist who can evaluate '
        'your skin in person. Is there a specific aspect of your skin concerns '
        'I can help you understand better, or a question to bring to your '
        'next appointment?';
  }

  void _scrollToBottom({bool delayed = false}) {
    void doScroll() {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    }

    if (delayed) {
      Future.delayed(const Duration(milliseconds: 120), doScroll);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _disclaimerBanner(),
          if (_suggestions.isNotEmpty && !_hasUserMessage) _suggestionChips(),
          Expanded(child: _messageList()),
          _inputRow(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.cardBackground,
      foregroundColor: AppColors.refinedSlate,
      elevation: 0,
      surfaceTintColor: AppColors.cardBackground,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.goldHover, AppColors.champagneGold],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.champagneGold.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              size: 18,
              color: AppColors.onChampagneGold,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'AI Nurse',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.refinedSlate,
                ),
              ),
              Text(
                'General wellness guidance',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.refinedSlate.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _disclaimerBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.12),
            AppColors.champagneGold.withValues(alpha: 0.05),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: AppColors.champagneGold.withValues(alpha: 0.32),
            width: 0.7,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                size: 17,
                color: AppColors.goldHover,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.refinedSlate.withValues(alpha: 0.9),
                    ),
                    children: const [
                      TextSpan(
                        text:
                            'AI Nurse provides general wellness and educational information only. ',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      TextSpan(
                        text:
                            'This is NOT medical advice or a diagnosis. '
                            'Always consult a qualified dermatologist.',
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

  Widget _messageList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) return _typingIndicator();
        return _messageBubble(_messages[i]);
      },
    );
  }

  Widget _messageBubble(_ChatMessage msg) {
    final isUser = msg.role == _Role.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.goldHover, AppColors.champagneGold],
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      size: 12,
                      color: AppColors.onChampagneGold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'AI Nurse',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.refinedSlate.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: isUser ? null : AppColors.cardBackground,
                gradient: isUser
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.goldHover, AppColors.champagneGold],
                      )
                    : null,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: AppColors.champagneGold.withValues(alpha: 0.22),
                        width: 0.8,
                      ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isUser
                                ? AppColors.champagneGold
                                : AppColors.refinedSlate)
                            .withValues(alpha: isUser ? 0.28 : 0.06),
                    blurRadius: isUser ? 16 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isUser
                      ? AppColors.onChampagneGold
                      : AppColors.refinedSlate,
                ),
              ),
            ),
            if (msg.disclaimer != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 10,
                      color: AppColors.refinedSlate.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        msg.disclaimer!,
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.35,
                          color: AppColors.refinedSlate.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(
            color: AppColors.champagneGold.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              _TypingDot(delay: Duration(milliseconds: i * 160)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _suggestionChips() {
    return Container(
      color: AppColors.warmAlabaster,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
            height: 1,
            color: AppColors.champagneGold.withValues(alpha: 0.16),
          ),
          const SizedBox(height: 8),
          Text(
            'Suggested questions',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: AppColors.refinedSlate.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in _suggestions.take(5))
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 6),
                    child: GestureDetector(
                      onTap: () => _sendMessage(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.10,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.40,
                            ),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          s,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.refinedSlate,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputRow() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        8,
        8 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.champagneGold.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: _sendMessage,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.refinedSlate,
              ),
              decoration: InputDecoration(
                hintText: 'Ask a wellness question…',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.refinedSlate.withValues(alpha: 0.5),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.champagneGold.withValues(alpha: 0.30),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.champagneGold.withValues(alpha: 0.30),
                    width: 0.8,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.champagneGold.withValues(alpha: 0.75),
                    width: 1.2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                filled: true,
                fillColor: AppColors.warmAlabaster.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              boxShadow: _sending
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.champagneGold.withValues(alpha: 0.40),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
            ),
            child: Material(
              color: _sending
                  ? AppColors.refinedSlate.withValues(alpha: 0.18)
                  : AppColors.champagneGold,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: _sending ? null : () => _sendMessage(_input.text),
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  child: _sending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.refinedSlate.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          size: 19,
                          color: AppColors.onChampagneGold,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────

enum _Role { user, nurse }

class _ChatMessage {
  final _Role role;
  final String text;
  final String? disclaimer;
  final bool isDisclaimer;

  const _ChatMessage({
    required this.role,
    required this.text,
    this.disclaimer,
    this.isDisclaimer = false,
  });
}

// ─── Animated typing dots ─────────────────────────────────────────────────────

class _TypingDot extends StatefulWidget {
  final Duration delay;

  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.champagneGold,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
