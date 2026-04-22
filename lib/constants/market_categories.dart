// lib/constants/market_categories.dart

import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';

class MarketCategory {
  final String slug;
  final String label;
  final String labelTr;
  final String emoji;
  final Color color;

  const MarketCategory({
    required this.slug,
    required this.label,
    required this.labelTr,
    required this.emoji,
    required this.color,
  });
}

const kMarketCategories = <MarketCategory>[
  MarketCategory(
      slug: 'alcohol-cigarette',
      label: 'Alcohol & Cigarette',
      labelTr: 'Alkol & Sigara',
      emoji: '🍷',
      color: Color(0xFFF43F5E)),
  MarketCategory(
      slug: 'snack',
      label: 'Snack',
      labelTr: 'Atıştırmalık',
      emoji: '🍪',
      color: Color(0xFFF59E0B)),
  MarketCategory(
      slug: 'drinks',
      label: 'Drinks',
      labelTr: 'İçecekler',
      emoji: '☕',
      color: Color(0xFFF97316)),
  MarketCategory(
      slug: 'water',
      label: 'Water',
      labelTr: 'Su',
      emoji: '💧',
      color: Color(0xFF0EA5E9)),
  MarketCategory(
      slug: 'fruit-vegetables',
      label: 'Fruit & Vegetables',
      labelTr: 'Meyve & Sebze',
      emoji: '🍎',
      color: Color(0xFF22C55E)),
  MarketCategory(
      slug: 'food',
      label: 'Food',
      labelTr: 'Gıda',
      emoji: '🍽️',
      color: Color(0xFFEF4444)),
  MarketCategory(
      slug: 'meat-chicken-fish',
      label: 'Meat, Chicken & Fish',
      labelTr: 'Et, Tavuk & Balık',
      emoji: '🥩',
      color: Color(0xFF78716C)),
  MarketCategory(
      slug: 'basic-food',
      label: 'Basic Food',
      labelTr: 'Temel Gıda',
      emoji: '🌾',
      color: Color(0xFFEAB308)),
  MarketCategory(
      slug: 'dairy-breakfast',
      label: 'Dairy & Breakfast',
      labelTr: 'Süt Ürünleri & Kahvaltılık',
      emoji: '🥚',
      color: Color(0xFF84CC16)),
  MarketCategory(
      slug: 'bakery',
      label: 'Bakery',
      labelTr: 'Fırın & Unlu Mamüller',
      emoji: '🥐',
      color: Color(0xFFF59E0B)),
  MarketCategory(
      slug: 'ice-cream',
      label: 'Ice Cream',
      labelTr: 'Dondurma',
      emoji: '🍦',
      color: Color(0xFFEC4899)),
  MarketCategory(
      slug: 'fit-form',
      label: 'Fit & Form',
      labelTr: 'Fit & Form',
      emoji: '💪',
      color: Color(0xFF10B981)),
  MarketCategory(
      slug: 'home-care',
      label: 'Home Care',
      labelTr: 'Ev Bakım',
      emoji: '🧹',
      color: Color(0xFF3B82F6)),
  MarketCategory(
      slug: 'home-lite',
      label: 'Home Lite',
      labelTr: 'Ev Gereçleri',
      emoji: '💡',
      color: Color(0xFF6366F1)),
  MarketCategory(
      slug: 'personal-care',
      label: 'Personal Care',
      labelTr: 'Kişisel Bakım',
      emoji: '✨',
      color: Color(0xFF8B5CF6)),
  MarketCategory(
      slug: 'technology',
      label: 'Technology',
      labelTr: 'Teknoloji',
      emoji: '📱',
      color: Color(0xFF64748B)),
  MarketCategory(
      slug: 'sexual-health',
      label: 'Sexual Health',
      labelTr: 'Cinsel Sağlık',
      emoji: '❤️',
      color: Color(0xFFD946EF)),
  MarketCategory(
      slug: 'baby',
      label: 'Baby',
      labelTr: 'Bebek',
      emoji: '👶',
      color: Color(0xFF06B6D4)),
  MarketCategory(
      slug: 'clothing',
      label: 'Clothing',
      labelTr: 'Giyim',
      emoji: '👕',
      color: Color(0xFFA855F7)),
  MarketCategory(
      slug: 'stationery',
      label: 'Stationery',
      labelTr: 'Kırtasiye',
      emoji: '✏️',
      color: Color(0xFF14B8A6)),
  MarketCategory(
      slug: 'pet',
      label: 'Pet',
      labelTr: 'Evcil Hayvan',
      emoji: '🐶',
      color: Color(0xFFF97316)),
  MarketCategory(
      slug: 'tools',
      label: 'Tools',
      labelTr: 'Hırdavat & Alet',
      emoji: '🔧',
      color: Color(0xFF71717A)),
];

/// O(1) lookup by slug.
final kMarketCategoryMap = Map<String, MarketCategory>.fromEntries(
  kMarketCategories.map((c) => MapEntry(c.slug, c)),
);

extension MarketCategoryL10n on MarketCategory {
  String localizedLabel(AppLocalizations l10n) {
    switch (slug) {
      case 'alcohol-cigarette':
        return l10n.marketCategoryAlcoholCigarette;
      case 'snack':
        return l10n.marketCategorySnack;
      case 'drinks':
        return l10n.marketCategoryDrinks;
      case 'water':
        return l10n.marketCategoryWater;
      case 'fruit-vegetables':
        return l10n.marketCategoryFruitVegetables;
      case 'food':
        return l10n.marketCategoryFood;
      case 'meat-chicken-fish':
        return l10n.marketCategoryMeatChickenFish;
      case 'basic-food':
        return l10n.marketCategoryBasicFood;
      case 'dairy-breakfast':
        return l10n.marketCategoryDairyBreakfast;
      case 'bakery':
        return l10n.marketCategoryBakery;
      case 'ice-cream':
        return l10n.marketCategoryIceCream;
      case 'fit-form':
        return l10n.marketCategoryFitForm;
      case 'home-care':
        return l10n.marketCategoryHomeCare;
      case 'home-lite':
        return l10n.marketCategoryHomeLite;
      case 'personal-care':
        return l10n.marketCategoryPersonalCare;
      case 'technology':
        return l10n.marketCategoryTechnology;
      case 'sexual-health':
        return l10n.marketCategorySexualHealth;
      case 'baby':
        return l10n.marketCategoryBaby;
      case 'clothing':
        return l10n.marketCategoryClothing;
      case 'stationery':
        return l10n.marketCategoryStationery;
      case 'pet':
        return l10n.marketCategoryPet;
      case 'tools':
        return l10n.marketCategoryTools;
      default:
        return labelTr;
    }
  }
}
