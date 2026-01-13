import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../generated/l10n/app_localizations.dart'; // Ensure you have generated localization files

class PlaypointScreen extends StatefulWidget {
  /// Expect the [userId] to be passed in.
  final String? userId;
  const PlaypointScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<PlaypointScreen> createState() => _PlaypointScreenState();
}

class _PlaypointScreenState extends State<PlaypointScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<DocumentSnapshot<Map<String, dynamic>>> _getUserData() async {
    final uid = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception("User not logged in");
    }
    return _firestore.collection('users').doc(uid).get();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).referralCopied)),
    );
  }

  void _shareReferralCode(String code) {
    Share.share("Join me on [Your App Name]! Use my referral code: $code");
  }

  Widget _buildReferralList(String uid) {
    // Listen to the "referral" subcollection under the user's document.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('users')
          .doc(uid)
          .collection('referral')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              AppLocalizations.of(context).noReferrals,
              style: const TextStyle(fontSize: 14),
            ),
          );
        }
        final referrals = snapshot.data!.docs;
        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: referrals.length,
          separatorBuilder: (context, index) => Divider(
            color: Theme.of(context).dividerColor.withOpacity(0.2),
            thickness: 0.5,
            height: 0.5,
          ),
          itemBuilder: (context, index) {
            final referralData = referrals[index].data();
            final email = referralData['email'] ?? '';
            final timestamp = referralData['registeredAt'] as Timestamp?;
            final dateString = timestamp != null
                ? DateTime.fromMillisecondsSinceEpoch(
                        timestamp.millisecondsSinceEpoch)
                    .toLocal()
                    .toString()
                : '';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 0),
              leading: Icon(Icons.email,
                  color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
              title: Text(
                email,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: dateString.isNotEmpty
                  ? Text(
                      AppLocalizations.of(context).joined(dateString),
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
              dense: true,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Accent color for icon buttons (like copy/share).
    const Color goldColor = Color(0xFFFFD700);
    // Coral color for PlayPoints value.
    const Color coralColor = Color(0xFFFF7F50);

    // Define a light card color for light mode.
    final Color lightCardColor = Colors.white;
    // For dark mode, use a slightly darker variant.
    final Color darkCardColor = Colors.grey.shade900;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          AppLocalizations.of(context).playPointsTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Container(
        decoration: isDark
            ? const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1c1c1e), Color(0xFF2c2c2e)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              )
            : const BoxDecoration(
                color: Colors.white,
              ),
        child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: _getUserData(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !(snapshot.data?.exists ?? false)) {
              return Center(
                  child: Text(AppLocalizations.of(context).userDataNotFound));
            }

            final data = snapshot.data!.data()!;
            final String displayName = data['displayName'] ?? "User";
            final int playPoints = data['playPoints'] ?? 0;
            // For this approach, we use the user's own UID as the referral code.
            final String referralCode =
                data['referralCode'] ?? (widget.userId ?? "");
            final String profileImage = data['profileImage'] ??
                "https://via.placeholder.com/150"; // default placeholder image

            final uid = widget.userId ?? FirebaseAuth.instance.currentUser!.uid;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Section using Card
                  Card(
                    color: isDark ? darkCardColor : lightCardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade300,
                            backgroundImage: NetworkImage(profileImage),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white
                                    : Colors.grey.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // PlayPoints Section using Card
                  Card(
                    color: isDark ? darkCardColor : lightCardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.stars,
                            color: isDark ? Colors.white : Colors.grey.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                text:
                                    '${AppLocalizations.of(context).playPointsTitle}: ',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey.shade900,
                                ),
                                children: <TextSpan>[
                                  TextSpan(
                                    text: '$playPoints',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: coralColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Referral Code Section using Card
                  Card(
                    color: isDark ? darkCardColor : lightCardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            AppLocalizations.of(context).yourReferralCode,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  referralCode,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.grey.shade900,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                color: goldColor,
                                onPressed: () => _copyToClipboard(referralCode),
                                tooltip:
                                    AppLocalizations.of(context).copyTooltip,
                              ),
                              IconButton(
                                icon: const Icon(Icons.share),
                                color: goldColor,
                                onPressed: () =>
                                    _shareReferralCode(referralCode),
                                tooltip:
                                    AppLocalizations.of(context).shareTooltip,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Referral List Section using Card
                  Card(
                    color: isDark ? darkCardColor : lightCardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).invitedUsers,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade800,
                            ),
                          ),
                          Divider(
                            color:
                                isDark ? Colors.white24 : Colors.grey.shade400,
                            thickness: 0.5,
                            height: 12,
                          ),
                          _buildReferralList(uid),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
