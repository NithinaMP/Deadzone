import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showSender; // true in the Lobby so you see who said what

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showSender = false,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine ? AppColors.signal : AppColors.surfaceRaised;
    final textColor = isMine ? Colors.black : AppColors.textPrimary;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender && !isMine && message.senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.senderName,
                  style: const TextStyle(
                    color: AppColors.secure,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Text(
              message.decryptedText ?? '[unable to decrypt]',
              style: TextStyle(color: textColor, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  message.isBroadcast ? Icons.groups : Icons.lock,
                  size: 11,
                  color: textColor.withOpacity(0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTime(message.sentAt),
                  style: TextStyle(
                      fontSize: 10, color: textColor.withOpacity(0.6)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}