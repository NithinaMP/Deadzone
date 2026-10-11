/// Turns a name like "Sneaky Panda" into a matching emoji avatar.
const Map<String, String> _animalEmojis = {
  'panda': '🐼',
  'otter': '🦦',
  'llama': '🦙',
  'penguin': '🐧',
  'koala': '🐨',
  'gecko': '🦎',
  'walrus': '🦭',
  'narwhal': '🐳',
  'hedgehog': '🦔',
  'capybara': '🐹',
  'quokka': '🐿️',
  'axolotl': '🐸',
};

String avatarEmojiFor(String name) {
  final lower = name.toLowerCase();
  for (final entry in _animalEmojis.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return '😎';
}