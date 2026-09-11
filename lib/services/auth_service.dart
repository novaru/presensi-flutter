import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _googleInitialized = false;

  /// OAuth web client ID (Firebase console → Authentication → Sign-in
  /// method → Google). Public identifier, safe to ship in the app.
  static const _serverClientId =
      '895907179885-70rb5sagpvcp0ikddn9h2nukro8j5nm9.apps.googleusercontent.com';

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// v7 requires initialize() exactly once before any other GoogleSignIn
  /// call, with serverClientId on Android.
  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
    _googleInitialized = true;
  }

  /// Interactive Google sign-in, linked to Firebase Auth.
  /// Throws [GoogleSignInException] with code `canceled` when the user
  /// dismisses the account picker.
  Future<UserCredential> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await _ensureGoogleInitialized();
    await Future.wait([
      _auth.signOut(),
      GoogleSignIn.instance.signOut(),
    ]);
  }
}
