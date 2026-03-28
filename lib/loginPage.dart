import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ProfilePage.dart';
import 'listPage.dart';
import 'dart:ui';

class EmailAuthPage extends StatefulWidget {
  const EmailAuthPage({super.key});

  @override
  State<EmailAuthPage> createState() => _EmailAuthPageState();
}

class _EmailAuthPageState extends State<EmailAuthPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController numberController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool isLogin = true;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkAlreadyLoggedIn();
    });
  }

  void showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void checkAlreadyLoggedIn() async {
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        var doc = await _firestore.collection("profiles").doc(user.uid).get();
        if (!mounted) return;

        if (doc.exists && (doc.data()?['name'] ?? '').isNotEmpty) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const FriendsListPage()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSetupPage()),
          );
        }
      } catch (e) {
        showMessage("Database access error ❌");
      }
    }
  }

  Future<void> signUp() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final number = numberController.text.trim();

    if (email.isEmpty || password.isEmpty || number.isEmpty) {
      showMessage("Enter email, password, and number");
      return;
    }

    setState(() => loading = true);

    try {
      final query = await _firestore
          .collection("users")
          .where("number", isEqualTo: number)
          .get();

      if (query.docs.isNotEmpty) {
        showMessage("Number already registered ❌");
        setState(() => loading = false);
        return;
      }

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = userCredential.user!.uid;

      await _firestore.collection("users").doc(uid).set({
        "number": number,
        "email": email,
        "createdAt": FieldValue.serverTimestamp(),
      });

      await _firestore.collection("profiles").doc(uid).set({
        "uid": uid,
        "name": "",
        "profileImage": "",
      });

      showMessage("Registered Successfully ✅");
      emailController.clear();
      passwordController.clear();
      numberController.clear();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSetupPage()),
      );
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? "Signup Failed ❌");
    } on FirebaseException catch (e) {
      showMessage(e.message ?? "Database permission error ❌");
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showMessage("Enter email & password");
      return;
    }

    setState(() => loading = true);

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCredential.user!.uid;
      final doc = await _firestore.collection("profiles").doc(uid).get();
      final data = doc.data() ?? {};

      if (!mounted) return;

      if ((data['name'] ?? "").isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const FriendsListPage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSetupPage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? "Login Failed ❌");
    } on FirebaseException catch (e) {
      showMessage(e.message ?? "Database permission error ❌");
    } finally {
      setState(() => loading = false);
    }
  }

  InputDecoration customInput(String label, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.white70),
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(isLogin ? "Login" : "Register"),
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0F2027),
              Color(0xFF203A43),
              Color(0xFF2C5364),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),

        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),

            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),

                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),

                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      const Icon(Icons.chat, size: 60, color: Colors.white),
                      const SizedBox(height: 10),

                      Text(
                        "Welcome Back",
                        style: TextStyle(
                          fontSize: 22,
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 20),

                      TextField(
                        controller: emailController,
                        style: const TextStyle(color: Colors.white),
                        decoration: customInput("Email", Icons.email),
                      ),

                      const SizedBox(height: 15),

                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: customInput("Password", Icons.lock),
                      ),

                      const SizedBox(height: 15),

                      if (!isLogin)
                        TextField(
                          controller: numberController,
                          style: const TextStyle(color: Colors.white),
                          decoration: customInput("Number", Icons.phone),
                        ),

                      const SizedBox(height: 25),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: loading
                              ? null
                              : isLogin
                              ? login
                              : signUp,
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: Ink(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                              ),
                              borderRadius:
                                  BorderRadius.all(Radius.circular(30)),
                            ),
                            child: Center(
                              child: loading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : Text(
                                      isLogin ? "Login" : "Register",
                                      style: const TextStyle(fontSize: 16),
                                    ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      TextButton(
                        onPressed: loading
                            ? null
                            : () => setState(() => isLogin = !isLogin),
                        child: Text(
                          isLogin
                              ? "Don't have account? Register"
                              : "Already have account? Login",
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}