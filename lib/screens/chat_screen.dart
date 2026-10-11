import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../models/peer_device.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String deviceId;
  final String displayName;
  const ChatScreen({
    super.key,
    required this.deviceId,
    required this.displayName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
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
    final sent = await provider.sendTextMessage(
      peerDeviceId: widget.deviceId,
      plainText: text,
    );
    if (!sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still saying hi to this phone… try again in a sec 👋'),
        ),
      );
    }
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
    final messages = provider.conversationWith(widget.deviceId);
    final inRange =
        provider.livePeerFor(widget.deviceId)?.status == PeerStatus.connected;
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.displayName),
            Text(
              inRange ? 'Right here with you' : 'Out of range — hopping through friends',
              style: TextStyle(
                fontSize: 11,
                color: inRange ? AppColors.signal : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No messages yet 👋\nSay hi! 🔒 Only you two can read this.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
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