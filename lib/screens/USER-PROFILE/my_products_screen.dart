import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/myproducts/listed_products_tab.dart';
import '../../providers/my_products_provider.dart';

class MyProductsScreen extends StatefulWidget {
  const MyProductsScreen({Key? key}) : super(key: key);

  @override
  State<MyProductsScreen> createState() => _MyProductsScreenState();
}

class _MyProductsScreenState extends State<MyProductsScreen> {
  // ✅ Cache colors as static constants to avoid recreation
  static const Color jadeGreen = Color(0xFF00A86B);
  static const Color _jadeGreenLight = Color(0x1A00A86B); // 10% opacity
  static const Color _jadeGreenBorder = Color(0x3300A86B); // 20% opacity

  // ✅ Pre-computed colors for dark/light modes
  static const Color _darkBackground = Color.fromARGB(255, 33, 31, 49);
  static const Color _lightBackground = Color(0xFFFAFAFA);
  static const Color _darkBorder = Color(0x0DFFFFFF); // 5% white
  static const Color _lightBorder = Color(0x0D000000); // 5% black

  bool _isDisposed = false;

  // ✅ FIX 1: Create provider instance once, outside build
  late final MyProductsProvider _myProductsProvider;

  @override
  void initState() {
    super.initState();
    _myProductsProvider = MyProductsProvider();
    _initializeScreen();
  }

  void _initializeScreen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed && mounted) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _myProductsProvider.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // ✅ FIX 2: Use ChangeNotifierProvider.value for existing instance
    return ChangeNotifierProvider.value(
      value: _myProductsProvider,
      child: Scaffold(
        backgroundColor:
            isDark ? theme.scaffoldBackgroundColor : _lightBackground,
        appBar: _MyProductsAppBar(isDark: isDark, theme: theme),
        body: const _MyProductsBody(),
      ),
    );
  }
}

// ✅ FIX 3: Extract AppBar to separate widget to prevent unnecessary rebuilds
class _MyProductsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isDark;
  final ThemeData theme;

  const _MyProductsAppBar({
    required this.isDark,
    required this.theme,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return PreferredSize(
      preferredSize: preferredSize,
      child: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color:
                isDark ? _MyProductsScreenState._darkBackground : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? _MyProductsScreenState._darkBorder
                    : _MyProductsScreenState._lightBorder,
                width: 1,
              ),
            ),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const _AppBarTitle(),
        actions: const [
          _ProductCountBadge(),
          SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: _MyProductsScreenState._jadeGreenLight,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: const Icon(
            Icons.inventory_2_rounded,
            color: _MyProductsScreenState.jadeGreen,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          l10n.myProducts,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontFamily: 'Figtree',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

// ✅ FIX 4: Isolate Consumer to only rebuild the badge
class _ProductCountBadge extends StatelessWidget {
  const _ProductCountBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Selector<MyProductsProvider, int>(
        selector: (_, provider) => provider.products.length,
        builder: (context, productCount, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: _MyProductsScreenState._jadeGreenLight,
              borderRadius: BorderRadius.all(Radius.circular(20)),
              border: Border.fromBorderSide(
                BorderSide(
                  color: _MyProductsScreenState._jadeGreenBorder,
                  width: 1,
                ),
              ),
            ),
            child: Text(
              '$productCount',
              style: const TextStyle(
                color: _MyProductsScreenState.jadeGreen,
                fontFamily: 'Figtree',
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MyProductsBody extends StatelessWidget {
  const _MyProductsBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ColoredBox(
      color: isDark
          ? theme.scaffoldBackgroundColor
          : _MyProductsScreenState._lightBackground,
      child: const ListedProductsTab(),
    );
  }
}
