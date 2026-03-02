// lib/screens/RESTAURANTS/restaurant_shell_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';

import 'restaurants_screen.dart';
import '../CART-FAVORITE/food_cart.dart';
import '../USER-PROFILE/my_orders_screen.dart';
import '../USER-PROFILE/profile_screen.dart';

class RestaurantShellScreen extends StatefulWidget {
  const RestaurantShellScreen({super.key});

  @override
  State<RestaurantShellScreen> createState() => _RestaurantShellScreenState();
}

class _RestaurantShellScreenState extends State<RestaurantShellScreen> {
  int _selectedIndex = 0;

  // Tab indices:
  // 0 = Nar24 (RestaurantsScreen — tap again to go back to market)
  // 1 = Food Cart
  // 2 = My Orders
  // 3 = Profile

  void _onNavItemTapped(int idx) {
    if (idx < 0 || idx > 3) return;

    if (idx != _selectedIndex) {
      setState(() => _selectedIndex = idx);
    } else if (idx == 0) {
      // Already on restaurant listing — navigate back to market
      context.go('/');
    }
  }

  Widget _buildBodyContent() {
    switch (_selectedIndex) {
      case 0:
        return const RestaurantsScreen();
      case 1:
        return const FoodCartScreen();
      case 2:
        return const MyOrdersScreen();
      case 3:
        return const ProfileScreen();
      default:
        return const RestaurantsScreen();
    }
  }

  Widget _buildNavItem(IconData icon, String label, bool isSelected) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color unselectedFill =
        dark ? Colors.white : const Color.fromARGB(255, 58, 58, 58);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: isSelected ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: isSelected
              ? ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.orange, Colors.pink],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  child: Icon(icon, size: 22, color: Colors.white),
                )
              : Icon(icon, size: 22, color: unselectedFill),
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
                FeatherIcons.home, 'Nar24', _selectedIndex == 0),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.shoppingBag, 'Food Cart', _selectedIndex == 1),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.clipboard, 'My Orders', _selectedIndex == 2),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.user, 'Profile', _selectedIndex == 3),
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

    return Scaffold(
      body: _buildBodyContent(),
      bottomNavigationBar: _buildBottomNavigation(dark, bottomPad),
    );
  }
}
