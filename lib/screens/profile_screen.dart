import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../utils/avatar.dart';

/// Change your name. Friends nearby see the new name right away.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _controller;
  late final String _originalName;

  @override
  void initState() {
    super.initState();
    _originalName = context.read<MeshProvider>().myDisplayName;
    _controller = TextEditingController(text: _originalName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave {
    final t = _controller.text.trim();
    return t.isNotEmpty && t != _originalName;
  }

  void _surpriseMe() {
    final provider = context.read<MeshProvider>();
    setState(() => _controller.text = provider.suggestFunName());
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    await context.read<MeshProvider>().updateDisplayName(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("You're now $name ${avatarEmojiFor(name)}")),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final name = _controller.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          Center(
            child: CircleAvatar(
              radius: 52,
              backgroundColor: AppColors.surfaceRaised,
              child: Text(
                avatarEmojiFor(name),
                style: const TextStyle(fontSize: 52),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLength: 20,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Your name'),
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
          const SizedBox(height: 4),
          const Text(
            'This is the name your friends see. No accounts, no internet 🎉',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}