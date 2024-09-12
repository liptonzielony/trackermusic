import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spotify_sdk/spotify_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: 'YOUR_FIREBASE_API_KEY',
      authDomain: 'YOUR_FIREBASE_AUTH_DOMAIN',
      projectId: 'YOUR_FIREBASE_PROJECT_ID',
      storageBucket: 'YOUR_FIREBASE_STORAGE_BUCKET',
      messagingSenderId: 'YOUR_FIREBASE_MESSAGING_SENDER_ID',
      appId: 'YOUR_FIREBASE_APP_ID',
    ),
  );  // Inicjalizacja Firebase
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google & Spotify Login',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginScreen(),
    );
  }
}

Future<User?> _signInWithGoogle(BuildContext context) async {
  try {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);

    // Sprawdzenie, czy użytkownik istnieje w Firestore
    await _checkUserInFirestore(userCredential.user, 'google');

    return userCredential.user;
  } catch (e) {
    print('Google login error: $e');
    return null;
  }
}

Future<String?> _loginWithSpotify(BuildContext context) async {
  const clientId = 'xd';
  const redirectUri = 'xd';
  const scopes = 'app-remote-control user-modify-playback-state playlist-read-private user-read-playback-state user-read-currently-playing';

  try {
    // Połącz się z Spotify Remote
    final result = await SpotifySdk.connectToSpotifyRemote(
      clientId: clientId,
      redirectUrl: redirectUri,
    );

    if (result) {
      // Uzyskaj token dostępu
      final token = await SpotifySdk.getAccessToken(
        clientId: clientId,
        redirectUrl: redirectUri,
        scope: scopes,
      );

      print('Spotify token: $token');

      // Sprawdzenie, czy użytkownik istnieje w Firestore
      await _checkUserInFirestore(null, 'spotify', token: token);

      return token;
    } else {
      print('Failed to connect to Spotify remote');
      return null;
    }
  } catch (e) {
    print('Spotify login error: $e');
    return null;
  }
}



Future<void> _checkUserInFirestore(User? user, String provider, {String? token}) async {
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  CollectionReference users = firestore.collection('users');

  if (user != null) {
    // Sprawdzamy, czy użytkownik istnieje w bazie danych
    DocumentSnapshot userDoc = await users.doc(user.uid).get();

    if (!userDoc.exists) {
      // Rejestrujemy nowego użytkownika w bazie danych
      await users.doc(user.uid).set({
        'displayName': user.displayName,
        'email': user.email,
        'provider': provider,
        'lastLogin': FieldValue.serverTimestamp(),
      });
    } else {
      // Użytkownik istnieje, aktualizujemy datę logowania
      await users.doc(user.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });
    }
  } else if (token != null) {
    // Logowanie przez Spotify, gdzie nie mamy `User` z Firebase
    QuerySnapshot query = await users.where('spotifyToken', isEqualTo: token).get();

    if (query.docs.isEmpty) {
      // Jeśli użytkownik nie istnieje, rejestrujemy go
      await users.add({
        'spotifyToken': token,
        'provider': provider,
        'lastLogin': FieldValue.serverTimestamp(),
      });
    } else {
      // Jeśli użytkownik istnieje, aktualizujemy datę logowania
      for (var doc in query.docs) {
        await users.doc(doc.id).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }
    }
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () async {
                final user = await _signInWithGoogle(context);
                if (user != null) {
                  print('Logged in with Google as ${user.displayName}');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(googleUser: user),
                    ),
                  );
                }
              },
              child: const Text('Login with Google'),
            ),
            const SizedBox(height: 20), // Odstęp między przyciskami
            
            ElevatedButton(
              onPressed: () async {
                final token = await _loginWithSpotify(context);
                if (token != null) {
                  print('Logged in with Spotify with token: $token');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(spotifyToken: token),
                    ),
                  );
                }
              },
              child: const Text('Login with Spotify'),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final User? googleUser;
  final String? spotifyToken;

  const HomeScreen({super.key, this.googleUser, this.spotifyToken});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (googleUser != null)
              Column(
                children: [
                  Text('Logged in as: ${googleUser!.displayName} (Google)'),
                  Text('Email: ${googleUser!.email}'),
                ],
              )
            else if (spotifyToken != null)
              Text('Logged in with Spotify (Token available)'),
            if (googleUser == null && spotifyToken == null)
              const Text('No user logged in.'),
          ],
        ),
      ),
    );
  }
}
