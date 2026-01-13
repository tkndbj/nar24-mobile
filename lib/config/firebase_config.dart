class FirebaseConfig {
  static const apiKey = String.fromEnvironment('API_KEY');
  static const authDomain = String.fromEnvironment('AUTH_DOMAIN');
  static const projectId = String.fromEnvironment('PROJECT_ID');
  static const storageBucket = String.fromEnvironment('STORAGE_BUCKET');
  static const messagingSenderId =
      String.fromEnvironment('MESSAGING_SENDER_ID');
  static const appId = String.fromEnvironment('APP_ID');
  static const measurementId = String.fromEnvironment('MEASUREMENT_ID');
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
}
