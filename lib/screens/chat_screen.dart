import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../models/peer_device.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final PeerDevice peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  Future<void> _send(MeshProvider provider) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final sent = await provider.sendTextMessage(peerId: widget.peer.id, plainText: text);
    if (!sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still shaking hands with this device — try again in a moment')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final messages = provider.conversationWith(widget.peer.id);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peer.displayName),
            Row(
              children: [
                Icon(Icons.lock, size: 11, color: AppColors.secure),
                const SizedBox(width: 4),
                const Text('End-to-end encrypted', style: TextStyle(fontSize: 11, color: AppColors.secure)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
              child: Text(
                'No messages yet.\nAnything you send here only this device can read —\nnot even the phones relaying it in between.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: messages.length,
              itemBuilder: (context, i) {
                final msg = messages[i];
                return MessageBubble(
                  message: msg,
                  isMine: msg.senderId == provider.myDeviceId,
                );
              },
            ),
          ),
          _buildInputBar(provider),
        ],
      ),
    );
  }

  Widget _buildInputBar(MeshProvider provider) {
    return Padding(
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
              decoration: const InputDecoration(hintText: 'Message...'),
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
    );
  }
}