import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../widgets/message_bubble.dart';

/// A group chat with everyone nearby who has Deadzone open.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(MeshProvider provider) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await provider.sendLobbyMessage(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final messages = provider.conversationWith(lobbyKey);
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('The Lobby 🛋️'),
            Text(
              'Everyone nearby can see this',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: const Text(
              'Say hi to everyone nearby who has Deadzone open. '
                  'Want privacy? Open a private chat instead 🔒',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? const Center(
              child: Text(
                'Nobody has said anything yet.\nBe the first! 👋',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: messages.length,
              itemBuilder: (context, i) => MessageBubble(
                message: messages[i],
                isMine: messages[i].senderId == provider.myDeviceId,
                showSender: true,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                        hintText: 'Say something to everyone…'),
                    onSubmitted: (_) => _send(provider),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: AppColors.signal,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward, color: Colors.black),
                    onPressed: () => _send(provider),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}