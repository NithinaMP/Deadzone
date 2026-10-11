import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../utils/avatar.dart';
import 'radar_screen.dart';

/// Shown once, the first time the app opens. No accounts and no internet:
/// you just pick the name your friends will see.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Starts with the fun name the app already made for you.
    _controller = TextEditingController(
      text: context.read<MeshProvider>().myDisplayName,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canContinue => _controller.text.trim().isNotEmpty;

  void _surpriseMe() {
    final provider = context.read<MeshProvider>();
    setState(() => _controller.text = provider.suggestFunName());
  }

  Future<void> _continue() async {
    final provider = context.read<MeshProvider>();
    await provider.completeOnboarding(_controller.text.trim());
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RadarScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _controller.text.trim();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.sensors, size: 48, color: AppColors.signal),
            const SizedBox(height: 12),
            const Text(
              'Welcome to Deadzone 👋',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Chat with people near you.\nNo internet, no accounts.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 28),
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.surfaceRaised,
                child: Text(
                  avatarEmojiFor(name),
                  style: const TextStyle(fontSize: 48),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 20,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration:
                    const InputDecoration(labelText: 'Pick your name'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Surprise me',
                  onPressed: _surpriseMe,
                  icon: const Text('🎲', style: TextStyle(fontSize: 26)),
                ),
              ],
            ),
            const Text(
              'Friends nearby will see this name. You can change it any time.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  _point('📡', 'Find friends nearby, even with zero signal'),
                  _point('🔒', 'Private chats only you two can read'),
                  _point('🤝', 'Messages hop through other phones to reach far friends'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _canContinue ? _continue : null,
              child: const Text("Let's go"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _point(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}