import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';

class ChatScreen extends StatefulWidget {
  final String friendUid;
  final String friendNumber;

  const ChatScreen({
    super.key,
    required this.friendUid,
    required this.friendNumber,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController messageController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _record = AudioRecorder();
  final ScrollController _scrollController = ScrollController();

  late String myUid;

  late final enc.Key key;
  late final enc.IV iv;
  late final enc.Encrypter encrypter;

  bool isRecording = false;
  String? recordingPath;
  Timer? _typingTimer;

  final Map<String, AudioPlayer> _audioPlayers = {};
  final Map<String, bool> _isPlaying = {};

  @override
  void initState() {
    super.initState();
    myUid = _auth.currentUser!.uid;
    key = enc.Key.fromUtf8('12345678901234567890123456789012');
    iv = enc.IV.fromUtf8('1234567890123456');
    encrypter = enc.Encrypter(enc.AES(key));
    _setOnlineStatus(true);
    messageController.addListener(() {
      final text = messageController.text.trim();
      _setTypingStatus(text.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _setOnlineStatus(false);
    _setTypingStatus(false);
    _typingTimer?.cancel();
    messageController.dispose();
    for (var player in _audioPlayers.values) player.dispose();
    _audioPlayers.clear();
    super.dispose();
  }

  void _setOnlineStatus(bool online) {
    _firestore.collection('profiles').doc(myUid).set({
      'online': online,
      if (!online) 'lastSeen': FieldValue.serverTimestamp(),
      if (!online) 'typingTo': null,
    }, SetOptions(merge: true));
  }

  void _setTypingStatus(bool isTyping) {
    _typingTimer?.cancel();
    if (isTyping) {
      _firestore.collection('profiles').doc(myUid).set({
        'typingTo': widget.friendUid,
      }, SetOptions(merge: true));
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _setTypingStatus(false);
      });
    } else {
      _firestore.collection('profiles').doc(myUid).set({
        'typingTo': null,
      }, SetOptions(merge: true));
      _typingTimer = null;
    }
  }

  String formatLastSeen(Timestamp? ts) {
    if (ts == null) return "";
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return "just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    if (diff.inDays == 0) {
      return "today at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } else if (diff.inDays == 1) {
      return "yesterday at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } else {
      return "${diff.inDays}d ago";
    }
  }

  String formatTimestamp(Timestamp? ts) {
    if (ts == null) return "";
    final dt = ts.toDate();
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String getChatId() {
    List<String> ids = [myUid, widget.friendUid];
    ids.sort();
    return ids.join('_');
  }

  String encryptMsg(String text) => encrypter.encrypt(text, iv: iv).base64;
  String decryptMsg(String text) => encrypter.decrypt64(text, iv: iv);

  Future<void> playAudio(String audioUrl, String messageId) async {
    try {
      if (_isPlaying[messageId] == true) {
        await _audioPlayers[messageId]?.stop();
        setState(() => _isPlaying[messageId] = false);
        return;
      }

      if (!_audioPlayers.containsKey(messageId)) {
        _audioPlayers[messageId] = AudioPlayer();
      }
      final player = _audioPlayers[messageId]!;
      setState(() => _isPlaying[messageId] = true);
      await player.setUrl(audioUrl);
      await player.play();

      player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          setState(() => _isPlaying[messageId] = false);
          player.seek(Duration.zero);
        }
      });
    } catch (e) {
      debugPrint('playAudio failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Cannot play audio: $e')));
      }
      setState(() => _isPlaying[messageId] = false);
    }
  }

  Future<void> stopAllAudio() async {
    for (var player in _audioPlayers.values) {
      await player.stop();
    }
    setState(() {
      for (var key in _isPlaying.keys) {
        _isPlaying[key] = false;
      }
    });
  }

  Future<bool> sendMessage(
    String text, {
    String? imageUrl,
    String? audioUrl,
  }) async {
    if (text.trim().isEmpty && imageUrl == null && audioUrl == null)
      return false;

    try {
      String chatId = getChatId();
      String? encryptedText = text.trim().isNotEmpty
          ? encryptMsg(text.trim())
          : null;

      Map<String, dynamic> messageData = {
        'sender': myUid,
        'receiver': widget.friendUid,
        'seen': false,
        'timestamp': FieldValue.serverTimestamp(),
      };
      if (encryptedText != null) messageData['message'] = encryptedText;
      if (imageUrl != null) messageData['image'] = imageUrl;
      if (audioUrl != null) messageData['audio'] = audioUrl;

      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(messageData);
      await _firestore.collection('chats').doc(chatId).set({
        'participants': [myUid, widget.friendUid],
        'lastMessage': text.trim().isNotEmpty
            ? text.trim()
            : (imageUrl != null ? "📷 Image" : "🎵 Audio"),
        'lastTimestamp': FieldValue.serverTimestamp(),
      });

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      _setTypingStatus(false);
      return true;
    } catch (e, st) {
      debugPrint('sendMessage failed: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message failed to send. Please try again.'),
          ),
        );
      }
      return false;
    }
  }

  Future<String> uploadImageToCloudinary(File file) async {
    const String cloudName = 'dvxnmsryu'; // बदला
    const String uploadPreset = 'flutter_upload'; // बदला

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder'] = 'chat_images'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Cloudinary upload failed ${response.statusCode}: $body');
    }
    final data = json.decode(body) as Map<String, dynamic>;
    if (data['secure_url'] == null) {
      throw Exception('Cloudinary response missing secure_url: $body');
    }
    return data['secure_url'] as String;
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (picked == null) return;

      final file = File(picked.path);
      if (!await file.exists()) {
        throw Exception('Selected image file does not exist: ${picked.path}');
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading image...')));

      final imageUrl = await uploadImageToCloudinary(file);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image uploaded successfully!')),
      );

      await sendMessage('', imageUrl: imageUrl);
    } catch (e, st) {
      debugPrint('pickImage failed: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to attach image right now: $e')),
        );
      }
    }
  }

  Future<void> startRecording() async {
    try {
      bool allowed = await _record.hasPermission();
      if (!allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required.')),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
      recordingPath = '${tempDir.path}/$fileName';

      if (!await Directory(tempDir.path).exists()) {
        await Directory(tempDir.path).create(recursive: true);
      }

      setState(() => isRecording = true);
      await _record.start(const RecordConfig(), path: recordingPath!);
      debugPrint('Recording started: $recordingPath');
    } catch (e, st) {
      debugPrint('startRecording failed: $e');
      debugPrint('$st');
      setState(() => isRecording = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Cannot start recording: $e')));
      }
    }
  }

  Future<void> stopRecording() async {
    try {
      if (recordingPath == null) {
        debugPrint('stopRecording: recordingPath is null');
        setState(() => isRecording = false);
        return;
      }

      debugPrint('Stopping recording at: $recordingPath');
      await _record.stop();
      setState(() => isRecording = false);

      final file = File(recordingPath!);
      if (await file.exists()) {
        debugPrint('Recording file size: ${await file.length()} bytes');
        String fileName = DateTime.now().millisecondsSinceEpoch.toString();
        try {
          TaskSnapshot snap = await _storage
              .ref('chat_audio/$fileName')
              .putFile(file);
          String audioUrl = await snap.ref.getDownloadURL();
          debugPrint('Audio uploaded: $audioUrl');
          await sendMessage("", audioUrl: audioUrl);
          try {
            await file.delete();
          } catch (e) {
            debugPrint('Failed to delete temp file: $e');
          }
        } catch (uploadError) {
          debugPrint('Upload error: $uploadError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload failed: $uploadError')),
            );
          }
        }
      } else {
        debugPrint('Recording file not found: $recordingPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording file not found.')),
          );
        }
      }
      recordingPath = null;
    } catch (e, st) {
      debugPrint('stopRecording failed: $e');
      debugPrint('$st');
      setState(() => isRecording = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      String chatId = getChatId();
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message deleted')));
      }
    } catch (e) {
      debugPrint('deleteMessage failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete message')),
        );
      }
    }
  }

  Future<void> deleteEntireChat() async {
    try {
      String chatId = getChatId();
      final messages = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      for (var message in messages.docs) {
        await message.reference.delete();
      }
      await _firestore.collection('chats').doc(chatId).delete();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chat deleted')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('deleteEntireChat failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to delete chat')));
      }
    }
  }

  void _showMessageOptions(String messageId, bool isMyMessage) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMyMessage)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete Message',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  deleteMessage(messageId);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                'Delete Entire Chat',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _showDeleteChatConfirmation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteChatConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat'),
        content: const Text(
          'Are you sure you want to delete this entire chat? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              deleteEntireChat();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _openEmojiPicker() {
    const emojis = ['😀', '😂', '😍', '😎', '😢', '🙏', '🔥', '❤️', '👍'];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: emojis
              .map(
                (e) => IconButton(
                  icon: Text(e, style: const TextStyle(fontSize: 26)),
                  onPressed: () {
                    messageController.text += e;
                    Navigator.of(ctx).pop();
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _openFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Container(
          color: Colors.black,
          child: Center(
            child: Hero(
              tag: imageUrl,
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 3.0,
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatId = getChatId();

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: StreamBuilder<DocumentSnapshot>(
          stream: _firestore
              .collection('profiles')
              .doc(widget.friendUid)
              .snapshots(),
          builder: (context, snapshot) {
            String profileImg = "";
            bool online = false;
            Timestamp? lastSeen;
            String? typingTo;

            final data = snapshot.hasData && snapshot.data!.exists
                ? snapshot.data!.data() as Map<String, dynamic>? ?? {}
                : <String, dynamic>{};

            profileImg = (data['profileImage'] as String?) ?? "";
            online = (data['online'] as bool?) ?? false;
            lastSeen = data['lastSeen'] as Timestamp?;
            typingTo = (data['typingTo'] as String?);

            final String name =
                (data['name'] as String?) ?? widget.friendNumber;
            final bool friendTyping = typingTo == myUid;

            final statusText = online
                ? 'online'
                : (lastSeen != null
                      ? 'last seen ${formatLastSeen(lastSeen)}'
                      : 'offline');

            final Widget statusWidget = friendTyping
                ? AnimatedTextKit(
                    animatedTexts: [
                      TyperAnimatedText(
                        'typing...',
                        textStyle: const TextStyle(
                          fontSize: 12,
                          color: Colors.lightGreenAccent,
                        ),
                      ),
                    ],
                    repeatForever: true,
                  )
                : Text(
                    statusText,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  );

            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: profileImg.isNotEmpty
                      ? NetworkImage(profileImg)
                      : null,
                  child: profileImg.isEmpty
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    statusWidget,
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          const Icon(Icons.video_call),
          const SizedBox(width: 10),
          const Icon(Icons.call),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete_chat') {
                _showDeleteChatConfirmation();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'delete_chat',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Chat', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D1F36), Color(0xFF012032), Color(0xFF081E37)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: kToolbarHeight + MediaQuery.of(context).padding.top,
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('chats')
                    .doc(chatId)
                    .collection('messages')
                    .orderBy('timestamp')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final messages = snapshot.data!.docs;
                  for (var msg in messages) {
                    final data = msg.data() as Map<String, dynamic>? ?? {};
                    if (data['receiver'] == myUid && data['seen'] == false) {
                      msg.reference.update({'seen': true});
                    }
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(10),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final data = msg.data() as Map<String, dynamic>? ?? {};
                      final isMe = data['sender'] == myUid;
                      final seen = data['seen'] ?? false;
                      final text = data['message'] != null
                          ? decryptMsg(data['message'])
                          : "";
                      final imageUrl = (data['image'] as String?) ?? "";
                      final audioUrl = (data['audio'] as String?) ?? "";
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () => _showMessageOptions(msg.id, isMe),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.72,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                                colors: [Color(0xFF1B2C3F), Color(0xFF233D54)],
                              ),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: isMe
                                    ? const Radius.circular(18)
                                    : const Radius.circular(4),
                                bottomRight: isMe
                                    ? const Radius.circular(4)
                                    : const Radius.circular(18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.22),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (text.isNotEmpty)
                                  Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: isMe
                                          ? Colors.white
                                          : Colors.white70,
                                      height: 1.35,
                                    ),
                                  ),
                                if (imageUrl.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: GestureDetector(
                                      onTap: () =>
                                          _openFullScreenImage(imageUrl),
                                      child: Hero(
                                        tag: imageUrl,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.network(
                                            imageUrl,
                                            height: 150,
                                            width: 150,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (context, child, progress) {
                                              if (progress == null)
                                                return child;
                                              return Container(
                                                height: 150,
                                                width: 150,
                                                color: Colors.black12,
                                                child: Center(
                                                  child: CircularProgressIndicator(
                                                    value:
                                                        progress.expectedTotalBytes !=
                                                            null
                                                        ? progress.cumulativeBytesLoaded /
                                                              progress
                                                                  .expectedTotalBytes!
                                                        : null,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              );
                                            },
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                                      height: 150,
                                                      width: 150,
                                                      color: Colors.black12,
                                                      child: const Icon(
                                                        Icons.broken_image,
                                                        color: Colors.redAccent,
                                                      ),
                                                    ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (audioUrl.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: GestureDetector(
                                      onTap: () => playAudio(audioUrl, msg.id),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade300,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _isPlaying[msg.id] == true
                                                  ? Icons.pause_circle
                                                  : Icons.play_circle,
                                              color: Colors.green,
                                              size: 28,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Audio',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                if (isMe)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        formatTimestamp(
                                          data['timestamp'] as Timestamp?,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(
                                        seen ? Icons.done_all : Icons.done,
                                        size: 15,
                                        color: seen ? Colors.blue : Colors.grey,
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.20),
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: _openEmojiPicker,
                              icon: const Icon(
                                Icons.emoji_emotions_outlined,
                                color: Colors.white70,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: messageController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: "Type a message",
                                  hintStyle: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (ctx) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.photo),
                                          title: const Text('Gallery'),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            pickImage(ImageSource.gallery);
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(
                                            Icons.insert_drive_file,
                                          ),
                                          title: const Text('Document'),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            pickImage(
                                              ImageSource.gallery,
                                            ); // तू same use करतोय
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.attach_file,
                                color: Colors.white70,
                              ),
                            ),

                            IconButton(
                              onPressed: () => pickImage(ImageSource.camera),
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white70,
                              ),
                            ),
                            GestureDetector(
                              onLongPress: startRecording,
                              onLongPressUp: stopRecording,
                              onTap: () async {
                                final text = messageController.text.trim();
                                if (text.isNotEmpty && !isRecording) {
                                  final ok = await sendMessage(text);
                                  if (ok) {
                                    messageController.clear();
                                  }
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                height: 44,
                                width: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: isRecording
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFFEA2C58),
                                            Color(0xFF8C0058),
                                          ],
                                        )
                                      : const LinearGradient(
                                          colors: [
                                            Color(0xFF00C3C9),
                                            Color(0xFF00787C),
                                          ],
                                        ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isRecording
                                          ? Colors.redAccent.withOpacity(0.6)
                                          : Colors.tealAccent.withOpacity(0.5),
                                      blurRadius: 12,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    isRecording ? Icons.mic : Icons.send,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isRecording ? 14 : 8),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 240),
                  opacity: 1,
                  // child: Text(
                  //   isRecording ? '🎤 Recording... release to send' : 'Long-press mic for voice message',
                  //   style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                  // ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
