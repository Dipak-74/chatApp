import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'landingPage.dart';

class FriendsListPage extends StatefulWidget {
  const FriendsListPage({super.key});

  @override
  State<FriendsListPage> createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage> {
  final TextEditingController searchController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Map<String, dynamic>>> getRegisteredUsers() {
    final myUid = _auth.currentUser!.uid;
    return _firestore
        .collection('friends')
        .doc(myUid)
        .collection('list')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              var data = doc.data();
              return {
                ...data,
                'online': data['online'] ?? false,
                'lastSeen': data['lastSeen'] ?? null,
              };
            }).toList());
  }

  void showAddFriendDialog() {
    TextEditingController numberController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.12),
                      Colors.white.withOpacity(0.05)
                    ],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_add,
                        color: Colors.tealAccent, size: 35),
                    const SizedBox(height: 10),
                    const Text("Add Friend",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 18),
                    TextField(
                      controller: numberController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Enter phone number",
                        hintStyle:
                            const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel",
                                style:
                                    TextStyle(color: Colors.white70)),
                          ),
                        ),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.tealAccent,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              String number =
                                  numberController.text.trim();

                              var userQuery = await _firestore
                                  .collection('users')
                                  .where('number', isEqualTo: number)
                                  .get();

                              if (userQuery.docs.isEmpty) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text("User Not Found ❌")),
                                );
                                return;
                              }

                              var userDoc = userQuery.docs.first;
                              final friendUid = userDoc.id;
                              final myUid =
                                  _auth.currentUser!.uid;

                              if (friendUid == myUid) return;

                              var profileDoc = await _firestore
                                  .collection('profiles')
                                  .doc(friendUid)
                                  .get();

                              String name =
                                  profileDoc.data()?['name'] ??
                                      'Unknown';
                              String? imageUrl =
                                  profileDoc.data()?[
                                      'profileImage'];
                              bool online =
                                  profileDoc.data()?['online'] ??
                                      false;
                              var lastSeen =
                                  profileDoc.data()?['lastSeen'];

                              String userUidLink =
                                  profileDoc.data()?['uid-u'] ??
                                      friendUid;

                              var numberDoc = await _firestore
                                  .collection('users')
                                  .doc(userUidLink)
                                  .get();

                              String friendNumber =
                                  numberDoc.data()?['number'] ??
                                      '';

                              await _firestore
                                  .collection('friends')
                                  .doc(myUid)
                                  .collection('list')
                                  .doc(friendUid)
                                  .set({
                                'uid': friendUid,
                                'name': name,
                                'number': friendNumber,
                                'profileImage': imageUrl,
                                'online': online,
                                'lastSeen': lastSeen,
                              });

                              Navigator.pop(context);
                            },
                            child: const Text("Add"),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String formatLastSeen(Timestamp? ts) {
    if (ts == null) return "";
    DateTime dt = ts.toDate();
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text("ChatApp",
        
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 255, 255, 255),
                fontSize: 28,
                letterSpacing: 1.5)),
        centerTitle: false,
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),

        child: Column(
          children: [
            const SizedBox(height: 120),

            // 🔍 Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: TextField(
                  controller: searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search,
                        color: Colors.white70),
                    hintText: "Search chats",
                    hintStyle:
                        TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 💬 LIST
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: getRegisteredUsers(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  var users = snapshot.data!;

                  return ListView.builder(
                    padding:
                        const EdgeInsets.only(bottom: 80),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];

                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(18),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.08),
                              Colors.white.withOpacity(0.02)
                            ],
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  friendUid: user['uid'],
                                  friendNumber:
                                      user['number'],
                                ),
                              ),
                            );
                          },
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundImage:
                                    user['profileImage'] != null
                                        ? NetworkImage(
                                            user['profileImage'])
                                        : null,
                                child:
                                    user['profileImage'] == null
                                        ? Text(
                                            user['name'][0]
                                                .toUpperCase(),
                                          )
                                        : null,
                              ),
                              if (user['online'])
                                Positioned(
                                  bottom: 2,
                                  right: 2,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration:
                                        const BoxDecoration(
                                      color:
                                          Colors.greenAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(user['name'],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight:
                                      FontWeight.bold)),
                          // subtitle: Text(
                          //   user['online']
                          //       ? "Online"
                          //       : "Last seen ${formatLastSeen(user['lastSeen'])}",
                          //   style: const TextStyle(
                          //       color: Colors.white60),
                          // ),
                          // trailing: Text(user['number'],
                          //     style: const TextStyle(
                          //         color: Colors.white54,
                          //         fontSize: 11)),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),

      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            backgroundColor: Colors.tealAccent,
            onPressed: showAddFriendDialog,
            child: const Icon(Icons.person_add,
                color: Colors.black),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            backgroundColor: Colors.redAccent,
            onPressed: () async {
              await _auth.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => const SplashPage()),
              );
            },
            child: const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }
}