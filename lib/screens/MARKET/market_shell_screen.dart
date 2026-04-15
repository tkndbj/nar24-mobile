// lib/screens/MARKET/market_shell_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:provider/provider.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../providers/market_cart_provider.dart';
import 'market_category_screen.dart';
import 'market_cart_screen.dart';
import 'my_market_orders_screen.dart';
import '../USER-PROFILE/profile_screen.dart';

class MarketShellScreen extends StatefulWidget {
  const MarketShellScreen({super.key});

  @override
  State<MarketShellScreen> createState() => _MarketShellScreenState();
}

class _MarketShellScreenState extends State<MarketShellScreen> {
  int _selectedIndex = 0;

  // Tab indices:
  // 0 = Nar24 (MarketCategoryScreen — tap again to go back to home)
  // 1 = Market Cart
  // 2 = My Orders
  // 3 = Profile

  void _onNavItemTapped(int idx) {
    if (idx < 0 || idx > 3) return;

    if (idx != _selectedIndex) {
      setState(() => _selectedIndex = idx);
    } else if (idx == 0) {
      // Already on market listing — navigate back to home
      context.go('/');
    }
  }

  Widget _buildBodyContent() {
    return IndexedStack(
      index: _selectedIndex,
      children: const [
        MarketCategoryScreen(),
        MarketCartScreen(),
        MyMarketOrdersScreen(),
        ProfileScreen(),
      ],
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isSelected,
      {int badgeCount = 0}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color unselectedFill =
        dark ? Colors.white : const Color.fromARGB(255, 58, 58, 58);

    Widget iconWidget = isSelected
        ? ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.orange, Colors.pink],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Icon(icon, size: 22, color: Colors.white),
          )
        : Icon(icon, size: 22, color: unselectedFill);

    if (badgeCount > 0) {
      iconWidget = Badge(
        label: Text(
          badgeCount > 99 ? '99+' : '$badgeCount',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.orange,
        child: iconWidget,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: isSelected ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: iconWidget,
        ),
        const SizedBox(height: 2),
        isSelected
            ? ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.orange, Colors.pink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: unselectedFill,
                  fontSize: 10,
                ),
              ),
      ],
    );
  }

  Widget _buildBottomNavigation(bool dark, double bottomPad) {
    final cartCount = context.watch<MarketCartProvider>().itemCount;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      height: 55 + bottomPad,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF211F31) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            spreadRadius: 2,
          )
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: Colors.transparent,
        unselectedItemColor: dark ? Colors.white : Colors.black,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: [
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.home, l10n.marketNavNar24, _selectedIndex == 0),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.shoppingBag, l10n.marketNavCart, _selectedIndex == 1,
                badgeCount: cartCount),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.clipboard, l10n.marketNavMyOrders, _selectedIndex == 2),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.user, l10n.marketNavProfile, _selectedIndex == 3),
            label: '',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: Scaffold(
        body: _buildBodyContent(),
        bottomNavigationBar: _buildBottomNavigation(dark, bottomPad),
      ),
    );
  }
}
