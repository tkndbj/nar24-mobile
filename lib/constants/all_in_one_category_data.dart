import '../generated/l10n/app_localizations.dart';
import '../models/product.dart';

/// A single utility class that stores all category + subcategory + sub-subcategory data
/// and provides localization helpers.
class AllInOneCategoryData {
  // ------------------------------------------------------
  // 1) Raw Data: Categories (Product-Based)
  // ------------------------------------------------------
  static const List<Map<String, String>> kCategories = [
    {'key': 'Clothing & Fashion'},
    {'key': 'Footwear'},
    {'key': 'Accessories'},
    {'key': 'Mother & Child'},
    {'key': 'Home & Furniture'},
    {'key': 'Beauty & Personal Care'},
    {'key': 'Bags & Luggage'},
    {'key': 'Electronics'},
    {'key': 'Flowers & Gifts'},
    {'key': 'Sports & Outdoor'},
    {'key': 'Books, Stationery & Hobby'},
    {'key': 'Tools & Hardware'},
    {'key': 'Pet Supplies'},
    {'key': 'Automotive'},
    {'key': 'Health & Wellness'},
  ];

  // ------------------------------------------------------
  // 2) Raw Data: Category Keywords
  // ------------------------------------------------------
  static const Map<String, List<String>> kCategoryKeywordsMap = {
    'Clothing & Fashion': [
      'clothing',
      'apparel',
      'fashion',
      'garments',
      'wear',
      'dress',
      'shirt',
      'pants',
      'underwear',
      'sleepwear',
      'sportswear',
      'swimwear',
    ],
    'Footwear': [
      'shoes',
      'boots',
      'sneakers',
      'sandals',
      'heels',
      'footwear',
      'athletic shoes',
      'dress shoes',
      'casual shoes',
    ],
    'Accessories': [
      'jewelry',
      'watches',
      'belts',
      'scarves',
      'hats',
      'gloves',
      'sunglasses',
      'ties',
      'cufflinks',
    ],
    'Mother & Child': [
      'baby',
      'kids',
      'children',
      'infant',
      'toddler',
      'maternity',
      'pregnancy',
      'toys',
      'baby care',
      'feeding',
      'safety',
      'strollers',
    ],
    'Home & Furniture': [
      'furniture',
      'home decor',
      'bedding',
      'kitchen',
      'bathroom',
      'lighting',
      'storage',
      'textiles',
      'appliances',
    ],
    'Beauty & Personal Care': [
      'skincare',
      'makeup',
      'cosmetics',
      'haircare',
      'fragrances',
      'personal care',
      'nail care',
      'body care',
      'grooming',
    ],
    'Bags & Luggage': [
      'bags',
      'handbags',
      'backpacks',
      'purses',
      'wallets',
      'luggage',
      'suitcases',
      'travel bags',
      'briefcases',
    ],
    'Electronics': [
      'electronics',
      'gadgets',
      'smartphones',
      'computers',
      'laptops',
      'tablets',
      'headphones',
      'cameras',
      'televisions',
      'gaming',
      'smart devices',
    ],
    'Flowers & Gifts': [
      'flowers',
      'bouquets',
      'arrangements',
      'plants',
      'gifts',
      'chocolate',
      'wreaths',
      'centerpieces',
      'floral',
      'potted plants',
      'flower delivery',
      'occasions',
    ],
    'Sports & Outdoor': [
      'sports',
      'fitness',
      'outdoor',
      'exercise',
      'camping',
      'hiking',
      'cycling',
      'running',
      'gym',
      'athletic',
    ],
    'Books, Stationery & Hobby': [
      'books',
      'stationery',
      'office supplies',
      'art supplies',
      'crafting',
      'hobby',
      'educational',
      'writing',
      'paper',
    ],
    'Tools & Hardware': [
      'tools',
      'hardware',
      'construction',
      'repair',
      'maintenance',
      'plumbing',
      'electrical',
      'automotive tools',
      'safety equipment',
    ],
    'Pet Supplies': [
      'dog supplies',
      'cat supplies',
      'bird supplies',
      'fish supplies',
      'small animals',
      'pet food',
      'pet care',
      'pet accessories',
    ],
    'Automotive': [
      'car parts',
      'auto accessories',
      'car care',
      'automotive tools',
      'tires',
      'car electronics',
      'motor oil',
      'car maintenance',
    ],
    'Health & Wellness': [
      'vitamins',
      'supplements',
      'medical supplies',
      'fitness equipment',
      'health monitors',
      'wellness products',
      'first aid',
      'mobility aids',
    ],
  };

  // ------------------------------------------------------
  // 3) Raw Data: Subcategories
  // ------------------------------------------------------
  static const Map<String, List<String>> kSubcategories = {
    'Clothing & Fashion': [
      'Dresses',
      'Tops & Shirts',
      'Bottoms',
      'Outerwear',
      'Underwear & Sleepwear',
      'Swimwear',
      'Activewear',
      'Suits & Formal',
      'Traditional & Cultural',
    ],
    'Footwear': [
      'Sneakers & Athletic',
      'Casual Shoes',
      'Formal Shoes',
      'Boots',
      'Sandals & Flip-Flops',
      'Slippers',
      'Specialized Footwear',
    ],
    'Accessories': [
      'Jewelry',
      'Watches',
      'Belts',
      'Hats & Caps',
      'Scarves & Wraps',
      'Sunglasses & Eyewear',
      'Gloves',
      'Hair Accessories',
      'Other Accessories',
    ],
    'Mother & Child': [
      'Baby Clothing',
      'Kids Clothing',
      'Kids Footwear',
      'Toys & Games',
      'Baby Care',
      'Maternity',
      'Strollers & Car Seats',
      'Feeding & Nursing',
      'Safety & Security',
      'Educational',
    ],
    'Home & Furniture': [
      'Living Room Furniture',
      'Bedroom Furniture',
      'Kitchen & Dining',
      'Bathroom',
      'Home Decor',
      'Lighting',
      'Storage & Organization',
      'Textiles & Soft Furnishing',
      'Garden & Outdoor',
    ],
    'Beauty & Personal Care': [
      'Skincare',
      'Makeup',
      'Haircare',
      'Fragrances',
      'Personal Hygiene',
      'Nail Care',
      'Body Care',
      'Oral Care',
      'Beauty Tools & Accessories',
    ],
    'Bags & Luggage': [
      'Handbags',
      'Backpacks',
      'Travel Luggage',
      'Briefcases & Business Bags',
      'Sports & Gym Bags',
      'Wallets & Small Accessories',
      'Specialty Bags',
    ],
    'Electronics': [
      'Smartphones & Accessories',
      'Computers & Laptops',
      'TVs & Home Entertainment',
      'Audio Equipment',
      'Gaming',
      'Smart Home & IoT',
      'Cameras & Photography',
      'Wearable Tech',
      'Home Appliances',
      'Personal Care Electronics',
    ],
    'Flowers & Gifts': [
      'Bouquets & Arrangements',
      'Potted Plants',
      'Gift Arrangements',
      'Flower Accessories',
      'Wreaths & Centerpieces',
    ],
    'Sports & Outdoor': [
      'Fitness & Exercise',
      'Sports',
      'Water Sports',
      'Outdoor & Camping',
      'Winter Sports',
      'Cycling',
      'Running & Athletics',
      'Sports Accessories',
      'Sportswear',
    ],
    'Books, Stationery & Hobby': [
      'Books & Literature',
      'Office & School Supplies',
      'Art & Craft Supplies',
      'Writing Instruments',
      'Paper Products',
      'Educational Materials',
      'Hobbies & Collections',
      'Musical Instruments',
    ],
    'Tools & Hardware': [
      'Hand Tools',
      'Power Tools',
      'Hardware & Fasteners',
      'Electrical Supplies',
      'Plumbing Supplies',
      'Building Materials',
      'Safety Equipment',
      'Measuring Tools',
      'Tool Storage',
    ],
    'Pet Supplies': [
      'Dog Supplies',
      'Cat Supplies',
      'Bird Supplies',
      'Fish & Aquarium',
      'Small Animal Supplies',
      'Pet Food & Treats',
      'Pet Care & Health',
      'Pet Accessories',
      'Pet Training',
    ],
    'Automotive': [
      'Car Parts & Components',
      'Car Electronics',
      'Car Care & Maintenance',
      'Tires & Wheels',
      'Interior Accessories',
      'Exterior Accessories',
      'Tools & Equipment',
      'Motorcycle Parts',
    ],
    'Health & Wellness': [
      'Vitamins & Supplements',
      'Medical Equipment',
      'First Aid & Safety',
      'Fitness & Exercise Equipment',
      'Health Monitoring',
      'Mobility & Daily Living',
      'Alternative Medicine',
      'Personal Care',
    ],
  };

  // ------------------------------------------------------
  // 4) Raw Data: Sub-subcategories
  // ------------------------------------------------------
  static final Map<String, Map<String, List<String>>> kSubSubcategories = {
    'Clothing & Fashion': {
      'Dresses': [
        'Casual Dresses',
        'Formal Dresses',
        'Evening Gowns',
        'Cocktail Dresses',
        'Maxi Dresses',
        'Mini Dresses',
        'Midi Dresses',
        'Wedding Dresses',
        'Sundresses',
      ],
      'Tops & Shirts': [
        'T-Shirts',
        'Shirts',
        'Blouses',
        'Tank Tops',
        'Polo Shirts',
        'Crop Tops',
        'Tunics',
        'Hoodies',
        'Sweatshirts',
      ],
      'Bottoms': [
        'Jeans',
        'Pants',
        'Shorts',
        'Skirts',
        'Leggings',
        'Joggers',
        'Capris',
        'Culottes',
      ],
      'Outerwear': [
        'Jackets',
        'Coats',
        'Blazers',
        'Cardigans',
        'Sweaters',
        'Vests',
        'Parkas',
        'Trench Coats',
        'Windbreakers',
      ],
      'Underwear & Sleepwear': [
        'Bras',
        'Panties',
        'Boxers',
        'Briefs',
        'Undershirts',
        'Sleepwear',
        'Pajamas',
        'Nightgowns',
        'Robes',
        'Socks',
        'Tights',
        'Fantasy',
      ],
      'Swimwear': [
        'Bikinis',
        'One-Piece Swimsuits',
        'Swim Shorts',
        'Boardshorts',
        'Cover-Ups',
        'Rashguards',
      ],
      'Activewear': [
        'Sports Bras',
        'Athletic Tops',
        'Athletic Bottoms',
        'Tracksuits',
        'Yoga Wear',
        'Running Gear',
        'Gym Wear',
      ],
      'Suits & Formal': [
        'Business Suits',
        'Tuxedos',
        'Formal Shirts',
        'Dress Pants',
        'Waistcoats',
        'Bow Ties',
        'Cufflinks',
      ],
      'Traditional & Cultural': [
        'Ethnic Wear',
        'Cultural Costumes',
        'Traditional Dresses',
        'Ceremonial Clothing',
      ],
    },
    'Footwear': {
      'Sneakers & Athletic': [
        'Running Shoes',
        'Basketball Shoes',
        'Training Shoes',
        'Casual Sneakers',
        'Skateboard Shoes',
        'Tennis Shoes',
        'Walking Shoes',
      ],
      'Casual Shoes': [
        'Loafers',
        'Boat Shoes',
        'Canvas Shoes',
        'Slip-On Shoes',
        'Espadrilles',
        'Moccasins',
      ],
      'Formal Shoes': [
        'Dress Shoes',
        'Oxford Shoes',
        'Derby Shoes',
        'Monk Strap Shoes',
        'Pumps',
        'High Heels',
        'Flats',
      ],
      'Boots': [
        'Ankle Boots',
        'Knee-High Boots',
        'Combat Boots',
        'Chelsea Boots',
        'Work Boots',
        'Hiking Boots',
        'Rain Boots',
        'Snow Boots',
      ],
      'Sandals & Flip-Flops': [
        'Flip-Flops',
        'Flat Sandals',
        'Heeled Sandals',
        'Sport Sandals',
        'Slides',
        'Gladiator Sandals',
      ],
      'Slippers': [
        'House Slippers',
        'Bedroom Slippers',
        'Moccasin Slippers',
        'Slipper Boots',
      ],
      'Specialized Footwear': [
        'Safety Shoes',
        'Medical Shoes',
        'Dance Shoes',
        'Cleats',
        'Climbing Shoes',
      ],
    },
    'Accessories': {
      'Jewelry': [
        'Necklaces',
        'Earrings',
        'Rings',
        'Bracelets',
        'Anklets',
        'Brooches',
        'Jewelry Sets',
        'Body Jewelry',
      ],
      'Watches': [
        'Analog Watches',
        'Digital Watches',
        'Smartwatches',
        'Sports Watches',
        'Luxury Watches',
        'Fashion Watches',
        'Kids Watches',
      ],
      'Belts': [
        'Leather Belts',
        'Fabric Belts',
        'Chain Belts',
        'Dress Belts',
        'Casual Belts',
        'Designer Belts',
      ],
      'Hats & Caps': [
        'Baseball Caps',
        'Beanies',
        'Fedoras',
        'Sun Hats',
        'Bucket Hats',
        'Berets',
        'Snapbacks',
      ],
      'Scarves & Wraps': [
        'Silk Scarves',
        'Winter Scarves',
        'Shawls',
        'Pashminas',
        'Bandanas',
        'Wraps',
      ],
      'Sunglasses & Eyewear': [
        'Sunglasses',
        'Reading Glasses',
        'Blue Light Glasses',
        'Safety Glasses',
        'Fashion Glasses',
      ],
      'Gloves': [
        'Winter Gloves',
        'Dress Gloves',
        'Work Gloves',
        'Sports Gloves',
        'Touchscreen Gloves',
      ],
      'Hair Accessories': [
        'Hair Clips',
        'Headbands',
        'Hair Ties',
        'Bobby Pins',
        'Hair Scarves',
        'Hair Jewelry',
      ],
      'Other Accessories': [
        'Keychains',
        'Phone Cases',
        'Wallets',
        'Purse Accessories',
        'Pins & Badges',
      ],
    },
    'Mother & Child': {
      'Baby Clothing': [
        'Bodysuits',
        'Rompers',
        'Baby Sets',
        'Baby Sleepwear',
        'Baby Socks',
        'Baby Hats',
        'Baby Mittens',
      ],
      'Kids Clothing': [
        'Kids T-Shirts',
        'Kids Pants',
        'Kids Dresses',
        'Kids Sweatshirts',
        'Kids Jackets',
        'Kids Pajamas',
        'School Uniforms',
      ],
      'Kids Footwear': [
        'Kids Sneakers',
        'Kids Sandals',
        'Kids Boots',
        'School Shoes',
        'Sports Shoes',
        'Rain Boots',
        'Kids Slippers',
      ],
      'Toys & Games': [
        'Educational Toys',
        'Plush Toys',
        'Building Blocks',
        'Dolls & Action Figures',
        'Puzzles',
        'Board Games',
        'Electronic Toys',
        'Outdoor Play',
      ],
      'Baby Care': [
        'Diapers',
        'Baby Wipes',
        'Baby Skincare',
        'Baby Bath Products',
        'Baby Health',
        'Baby Monitors',
      ],
      'Maternity': [
        'Maternity Clothing',
        'Nursing Bras',
        'Maternity Accessories',
        'Pregnancy Support',
      ],
      'Strollers & Car Seats': [
        'Strollers',
        'Car Seats',
        'Travel Systems',
        'Booster Seats',
        'Stroller Accessories',
      ],
      'Feeding & Nursing': [
        'Baby Bottles',
        'Breast Pumps',
        'Pacifiers',
        'High Chairs',
        'Feeding Accessories',
        'Baby Food',
      ],
      'Safety & Security': [
        'Baby Gates',
        'Outlet Covers',
        'Cabinet Locks',
        'Corner Guards',
        'Baby Monitors',
      ],
      'Educational': [
        'Learning Toys',
        'Educational Books',
        'Flash Cards',
        'Science Kits',
        'Musical Instruments',
      ],
    },
    'Home & Furniture': {
      'Living Room Furniture': [
        'Sofas',
        'Armchairs',
        'Coffee Tables',
        'TV Stands',
        'Bookcases',
        'Side Tables',
        'Ottoman',
        'Recliners',
      ],
      'Bedroom Furniture': [
        'Beds',
        'Mattresses',
        'Wardrobes',
        'Dressers',
        'Nightstands',
        'Mirrors',
        'Bed Frames',
        'Headboards',
      ],
      'Kitchen & Dining': [
        'Dining Tables',
        'Dining Chairs',
        'Bar Stools',
        'Kitchen Islands',
        'Cookware',
        'Dinnerware',
        'Glassware',
        'Kitchen Appliances',
        'Utensils',
      ],
      'Bathroom': [
        'Bathroom Vanities',
        'Shower Curtains',
        'Bath Mats',
        'Towel Racks',
        'Bathroom Storage',
        'Mirrors',
        'Accessories',
      ],
      'Home Decor': [
        'Wall Art',
        'Decorative Objects',
        'Candles',
        'Vases',
        'Picture Frames',
        'Clocks',
        'Artificial Plants',
        'Sculptures',
      ],
      'Lighting': [
        'Ceiling Lights',
        'Table Lamps',
        'Floor Lamps',
        'Wall Lights',
        'Pendant Lights',
        'Chandelier',
        'String Lights',
        'Night Lights',
      ],
      'Storage & Organization': [
        'Shelving Units',
        'Storage Boxes',
        'Baskets',
        'Hangers',
        'Closet Organizers',
        'Drawer Organizers',
        'Storage Bins',
      ],
      'Textiles & Soft Furnishing': [
        'Curtains',
        'Blinds',
        'Rugs',
        'Cushions',
        'Throws',
        'Bed Linens',
        'Towels',
        'Blankets',
      ],
      'Garden & Outdoor': [
        'Garden Furniture',
        'Plant Pots',
        'Garden Tools',
        'Outdoor Lighting',
        'BBQ & Grills',
        'Umbrellas',
        'Garden Decor',
      ],
    },
    'Beauty & Personal Care': {
      'Skincare': [
        'Cleansers',
        'Moisturizers',
        'Serums',
        'Face Masks',
        'Sunscreen',
        'Toners',
        'Eye Creams',
        'Anti-Aging',
        'Acne Treatment',
      ],
      'Makeup': [
        'Foundation',
        'Concealer',
        'Powder',
        'Blush',
        'Bronzer',
        'Highlighter',
        'Eyeshadow',
        'Eyeliner',
        'Mascara',
        'Lipstick',
        'Lip Gloss',
        'Makeup Brushes',
      ],
      'Haircare': [
        'Shampoo',
        'Conditioner',
        'Hair Masks',
        'Hair Oils',
        'Styling Products',
        'Hair Color',
        'Hair Tools',
      ],
      'Fragrances': [
        'Perfumes',
        'Eau de Toilette',
        'Body Sprays',
        'Deodorants',
        'Cologne',
        'Essential Oils',
      ],
      'Personal Hygiene': [
        'Body Wash',
        'Soap',
        'Shampoo',
        'Deodorants',
        'Feminine Care',
        'Men\'s Grooming',
        'Intimate Care',
      ],
      'Nail Care': [
        'Nail Polish',
        'Nail Tools',
        'Nail Treatments',
        'Nail Art',
        'Cuticle Care',
        'Nail Files',
      ],
      'Body Care': [
        'Body Lotions',
        'Body Oils',
        'Body Scrubs',
        'Hand Cream',
        'Foot Care',
        'Bath Products',
        'Massage Oils',
      ],
      'Oral Care': [
        'Toothbrushes',
        'Toothpaste',
        'Mouthwash',
        'Dental Floss',
        'Teeth Whitening',
        'Oral Health',
      ],
      'Beauty Tools & Accessories': [
        'Makeup Brushes',
        'Beauty Sponges',
        'Hair Brushes',
        'Mirrors',
        'Tweezers',
        'Nail Clippers',
        'Beauty Cases',
      ],
    },
    'Bags & Luggage': {
      'Handbags': [
        'Tote Bags',
        'Shoulder Bags',
        'Crossbody Bags',
        'Clutches',
        'Evening Bags',
        'Satchels',
        'Hobo Bags',
      ],
      'Backpacks': [
        'School Backpacks',
        'Travel Backpacks',
        'Laptop Backpacks',
        'Hiking Backpacks',
        'Casual Backpacks',
        'Kids Backpacks',
      ],
      'Travel Luggage': [
        'Suitcases',
        'Carry-On Bags',
        'Travel Duffel Bags',
        'Luggage Sets',
        'Garment Bags',
        'Travel Accessories',
      ],
      'Briefcases & Business Bags': [
        'Briefcases',
        'Laptop Bags',
        'Messenger Bags',
        'Portfolio Bags',
        'Business Totes',
      ],
      'Sports & Gym Bags': [
        'Gym Bags',
        'Sports Duffel Bags',
        'Equipment Bags',
        'Yoga Bags',
        'Swimming Bags',
      ],
      'Wallets & Small Accessories': [
        'Wallets',
        'Card Holders',
        'Coin Purses',
        'Key Cases',
        'Phone Cases',
        'Passport Holders',
      ],
      'Specialty Bags': [
        'Camera Bags',
        'Diaper Bags',
        'Lunch Bags',
        'Tool Bags',
        'Cosmetic Bags',
        'Beach Bags',
      ],
    },
    'Electronics': {
      'Smartphones & Accessories': [
        'Smartphones',
        'Phone Cases',
        'Screen Protectors',
        'Chargers',
        'Power Banks',
        'Phone Stands',
        'Wireless Chargers',
      ],
      'Computers & Laptops': [
        'Laptops',
        'Desktop Computers',
        'Tablets',
        'Monitors',
        'Keyboards',
        'Mice',
        'Laptop Accessories',
        'Computer Components',
      ],
      'TVs & Home Entertainment': [
        'Smart TVs',
        'Projectors',
        'Streaming Devices',
        'TV Mounts & Stands',
        'Home Theater Systems',
        'TV Cables & Accessories',
        'Remote Controls',
        'TV Antennas',
        'Media Players',
      ],
      'Audio Equipment': [
        'Headphones',
        'Earbuds',
        'Speakers',
        'Sound Systems',
        'Soundbars',
        'Microphones',
        'Amplifiers',
        'Turntables',
        'Audio Cables',
      ],
      'Gaming': [
        'Gaming Consoles',
        'Video Games',
        'Gaming Controllers',
        'Gaming Headsets',
        'Gaming Chairs',
        'VR Headsets',
        'Gaming Accessories',
      ],
      'Smart Home & IoT': [
        'Smart Speakers',
        'Smart Lights',
        'Smart Plugs',
        'Security Cameras',
        'Smart Thermostats',
        'Smart Locks',
        'Home Automation',
      ],
      'Cameras & Photography': [
        'Digital Cameras',
        'DSLR Cameras',
        'Action Cameras',
        'Camera Lenses',
        'Tripods',
        'Camera Accessories',
        'Photography Equipment',
      ],
      'Wearable Tech': [
        'Smartwatches',
        'Fitness Trackers',
        'Smart Glasses',
        'Health Monitors',
        'Wearable Accessories',
      ],
      'Home Appliances': [
        'Kitchen Appliances',
        'White Goods',
        'Air Conditioning',
        'Heating',
      ],
      'Personal Care Electronics': [
        'Hair Dryers',
        'Hair Straighteners',
        'Electric Shavers',
        'Toothbrushes',
        'Beauty Devices',
        'Health Monitors',
      ],
    },
    'Flowers & Gifts': {
      'Bouquets & Arrangements': [
        'Bouquets',
        'Flower Arrangements',
        'Mixed Arrangements',
        'Single Flower Types',
        'Seasonal Arrangements',
      ],
      'Potted Plants': [
        'Indoor Plants',
        'Outdoor Plants',
        'Succulents',
        'Orchids',
        'Bonsai',
        'Cacti',
      ],
      'Gift Arrangements': [
        'Chocolate Arrangements',
        'Edible Arrangements',
        'Fruit Baskets',
        'Gift Combos',
        'Balloon Arrangements',
      ],
      'Flower Accessories': [
        'Vases',
        'Planters & Pots',
        'Floral Foam',
        'Ribbons & Wraps',
        'Plant Care Products',
        'Decorative Accessories',
      ],
      'Wreaths & Centerpieces': [
        'Funeral Wreaths',
        'Decorative Wreaths',
        'Table Centerpieces',
        'Event Decorations',
        'Seasonal Wreaths',
      ],
    },
    'Sports & Outdoor': {
      'Fitness & Exercise': [
        'Cardio Equipment',
        'Strength Training',
        'Yoga Equipment',
        'Pilates Equipment',
        'Home Gym',
        'Exercise Accessories',
        'Recovery Equipment',
      ],
      'Sports': [
        'Football',
        'Basketball',
        'Baseball',
        'Volleyball',
        'Tennis',
        'Cricket',
        'American Football',
        'Golf',
        'Table Tennis',
        'Badminton',
      ],
      'Water Sports': [
        'Swimming',
        'Surfing',
        'Kayaking',
        'Diving',
        'Water Skiing',
        'Fishing',
        'Boating',
        'Water Safety',
      ],
      'Outdoor & Camping': [
        'Camping Gear',
        'Hiking Equipment',
        'Backpacking',
        'Climbing Gear',
        'Outdoor Clothing',
        'Navigation',
        'Survival Gear',
      ],
      'Winter Sports': [
        'Skiing',
        'Snowboarding',
        'Ice Skating',
        'Winter Clothing',
        'Snow Equipment',
        'Winter Accessories',
      ],
      'Cycling': [
        'Bicycles',
        'Bike Accessories',
        'Cycling Apparel',
        'Bike Maintenance',
        'Bike Safety',
        'E-Bikes',
      ],
      'Running & Athletics': [
        'Running Shoes',
        'Running Apparel',
        'Track & Field',
        'Marathon Gear',
        'Running Accessories',
        'Performance Monitoring',
      ],
      'Sports Accessories': [
        'Sports Bags',
        'Protective Gear',
        'Sports Nutrition',
        'Hydration',
        'Sports Technology',
        'Fan Gear',
      ],
      'Sportswear': [
        'Athletic Tops',
        'Athletic Bottoms',
        'Sports Bras',
        'Athletic Shoes',
        'Sports Accessories',
        'Team Jerseys',
      ],
    },
    'Books, Stationery & Hobby': {
      'Books & Literature': [
        'Fiction Books',
        'Non-Fiction Books',
        'Educational Books',
        'Children\'s Books',
        'Reference Books',
        'Magazines',
        'Comics',
        'E-Books',
      ],
      'Office & School Supplies': [
        'Notebooks',
        'Binders',
        'Folders',
        'Desk Accessories',
        'Calculators',
        'Labels',
        'Staplers',
        'Organizers',
      ],
      'Art & Craft Supplies': [
        'Drawing Supplies',
        'Painting Supplies',
        'Craft Materials',
        'Scrapbooking',
        'Sewing Supplies',
        'Jewelry Making',
        'Model Building',
      ],
      'Writing Instruments': [
        'Pens',
        'Pencils',
        'Markers',
        'Highlighters',
        'Fountain Pens',
        'Mechanical Pencils',
        'Erasers',
      ],
      'Paper Products': [
        'Copy Paper',
        'Specialty Paper',
        'Cardstock',
        'Envelopes',
        'Sticky Notes',
        'Index Cards',
        'Construction Paper',
      ],
      'Educational Materials': [
        'Learning Games',
        'Flash Cards',
        'Educational Toys',
        'Science Kits',
        'Math Tools',
        'Language Learning',
      ],
      'Hobbies & Collections': [
        'Board Games',
        'Puzzles',
        'Trading Cards',
        'Collectibles',
        'Model Kits',
        'Gaming Accessories',
      ],
      'Musical Instruments': [
        'String Instruments',
        'Wind Instruments',
        'Percussion',
        'Electronic Instruments',
        'Music Accessories',
        'Sheet Music',
      ],
    },
    'Tools & Hardware': {
      'Hand Tools': [
        'Hammers',
        'Screwdrivers',
        'Wrenches',
        'Pliers',
        'Saws',
        'Chisels',
        'Utility Knives',
        'Hand Tool Sets',
      ],
      'Power Tools': [
        'Drills',
        'Saws',
        'Sanders',
        'Grinders',
        'Routers',
        'Nail Guns',
        'Impact Drivers',
        'Multi-Tools',
      ],
      'Hardware & Fasteners': [
        'Screws',
        'Bolts & Nuts',
        'Nails',
        'Washers',
        'Anchors',
        'Hinges',
        'Handles & Knobs',
        'Chains',
      ],
      'Electrical Supplies': [
        'Wire & Cable',
        'Outlets & Switches',
        'Circuit Breakers',
        'Light Fixtures',
        'Electrical Tools',
        'Extension Cords',
      ],
      'Plumbing Supplies': [
        'Pipes & Fittings',
        'Valves',
        'Faucets',
        'Toilet Parts',
        'Drain Cleaners',
        'Pipe Tools',
        'Sealants',
      ],
      'Building Materials': [
        'Lumber',
        'Drywall',
        'Insulation',
        'Roofing Materials',
        'Flooring',
        'Concrete',
        'Paint',
      ],
      'Safety Equipment': [
        'Work Gloves',
        'Safety Glasses',
        'Hard Hats',
        'Ear Protection',
        'Respirators',
        'Safety Vests',
        'First Aid Kits',
      ],
      'Measuring Tools': [
        'Tape Measures',
        'Levels',
        'Squares',
        'Calipers',
        'Rulers',
        'Laser Levels',
        'Marking Tools',
      ],
      'Tool Storage': [
        'Tool Boxes',
        'Tool Bags',
        'Tool Chests',
        'Workshop Storage',
        'Tool Organizers',
      ],
    },
    'Pet Supplies': {
      'Dog Supplies': [
        'Dog Food',
        'Dog Toys',
        'Dog Beds',
        'Leashes & Collars',
        'Dog Clothing',
        'Dog Grooming',
        'Dog Training',
        'Dog Health Care',
      ],
      'Cat Supplies': [
        'Cat Food',
        'Cat Toys',
        'Cat Beds',
        'Litter & Boxes',
        'Cat Trees',
        'Cat Grooming',
        'Cat Carriers',
        'Cat Health Care',
      ],
      'Bird Supplies': [
        'Bird Food',
        'Bird Cages',
        'Bird Toys',
        'Bird Perches',
        'Bird Houses',
        'Bird Health Care',
        'Bird Accessories',
      ],
      'Fish & Aquarium': [
        'Fish Food',
        'Aquarium Tanks',
        'Aquarium Filters',
        'Aquarium Decorations',
        'Water Treatment',
        'Aquarium Lighting',
        'Fish Health Care',
      ],
      'Small Animal Supplies': [
        'Small Animal Food',
        'Cages & Habitats',
        'Small Animal Toys',
        'Bedding',
        'Water Bottles',
        'Exercise Equipment',
      ],
      'Pet Food & Treats': [
        'Dry Food',
        'Wet Food',
        'Treats & Snacks',
        'Supplements',
        'Special Diet Food',
        'Organic Food',
      ],
      'Pet Care & Health': [
        'Flea & Tick Control',
        'Vitamins & Supplements',
        'First Aid',
        'Dental Care',
        'Skin & Coat Care',
        'Health Monitoring',
      ],
      'Pet Accessories': [
        'Pet Carriers',
        'Pet Strollers',
        'Pet Gates',
        'Travel Accessories',
        'Pet ID Tags',
        'Cleanup Supplies',
      ],
      'Pet Training': [
        'Training Treats',
        'Training Tools',
        'Clickers',
        'Training Pads',
        'Behavioral Aids',
      ],
    },
    'Automotive': {
      'Car Parts & Components': [
        'Engine Parts',
        'Brake Components',
        'Suspension Parts',
        'Transmission Parts',
        'Exhaust Systems',
        'Filters',
        'Belts & Hoses',
      ],
      'Car Electronics': [
        'Car Audio',
        'GPS & Navigation',
        'Dash Cams',
        'Car Alarms',
        'Bluetooth Adapters',
        'Backup Cameras',
      ],
      'Car Care & Maintenance': [
        'Motor Oil',
        'Car Wash Products',
        'Wax & Polish',
        'Car Cleaners',
        'Maintenance Tools',
        'Fluids',
      ],
      'Tires & Wheels': [
        'Tires',
        'Wheels',
        'Tire Accessories',
        'Wheel Covers',
        'Tire Pressure Monitors',
      ],
      'Interior Accessories': [
        'Seat Covers',
        'Floor Mats',
        'Steering Wheel Covers',
        'Air Fresheners',
        'Interior Organizers',
        'Sunshades',
      ],
      'Exterior Accessories': [
        'Car Covers',
        'Roof Racks',
        'Running Boards',
        'Mud Flaps',
        'License Plate Frames',
        'Decals',
      ],
      'Tools & Equipment': [
        'Jump Starters',
        'Tire Gauges',
        'Mechanics Tools',
        'Car Jacks',
        'Emergency Kits',
        'Diagnostic Tools',
      ],
      'Motorcycle Parts': [
        'Motorcycle Parts',
        'Motorcycle Accessories',
        'Motorcycle Gear',
        'Helmets',
        'Protective Clothing',
      ],
    },
    'Health & Wellness': {
      'Vitamins & Supplements': [
        'Multivitamins',
        'Vitamin D',
        'Vitamin C',
        'B Vitamins',
        'Omega-3',
        'Probiotics',
        'Protein Supplements',
        'Herbal Supplements',
      ],
      'Medical Equipment': [
        'Blood Pressure Monitors',
        'Thermometers',
        'Glucose Meters',
        'Pulse Oximeters',
        'Stethoscopes',
        'Medical Scales',
      ],
      'First Aid & Safety': [
        'First Aid Kits',
        'Bandages',
        'Antiseptics',
        'Pain Relief',
        'Emergency Supplies',
        'Safety Equipment',
      ],
      'Fitness & Exercise Equipment': [
        'Home Gym Equipment',
        'Cardio Machines',
        'Weights & Dumbbells',
        'Resistance Bands',
        'Yoga Mats',
        'Exercise Bikes',
      ],
      'Health Monitoring': [
        'Fitness Trackers',
        'Smart Scales',
        'Heart Rate Monitors',
        'Sleep Trackers',
        'Health Apps',
      ],
      'Mobility & Daily Living': [
        'Mobility Aids',
        'Grab Bars',
        'Bath Safety',
        'Seat Cushions',
        'Daily Living Aids',
      ],
      'Alternative Medicine': [
        'Essential Oils',
        'Aromatherapy',
        'Massage Tools',
        'Acupuncture',
        'Natural Remedies',
      ],
      'Personal Care': [
        'Oral Care',
        'Incontinence Care',
        'Hearing Aids',
        'Vision Care',
        'Skin Care',
      ],
    },
  };

  // ------------------------------------------------------
  // 5) Raw Data: Category-specific keyword->subcategory
  // ------------------------------------------------------
  static const Map<String, Map<String, String>>
      kCategoryKeywordToSubcategoryMap = {
    'Clothing & Fashion': {
      'dress': 'Dresses',
      'shirt': 'Tops & Shirts',
      'pants': 'Bottoms',
      'jacket': 'Outerwear',
      'underwear': 'Underwear & Sleepwear',
      'swimwear': 'Swimwear',
      'sportswear': 'Activewear',
      'suit': 'Suits & Formal',
    },
    'Footwear': {
      'sneakers': 'Sneakers & Athletic',
      'casual shoes': 'Casual Shoes',
      'formal shoes': 'Formal Shoes',
      'boots': 'Boots',
      'sandals': 'Sandals & Flip-Flops',
      'slippers': 'Slippers',
    },
    'Accessories': {
      'jewelry': 'Jewelry',
      'watches': 'Watches',
      'belts': 'Belts',
      'hats': 'Hats & Caps',
      'scarves': 'Scarves & Wraps',
      'sunglasses': 'Sunglasses & Eyewear',
    },
    'Mother & Child': {
      'baby clothing': 'Baby Clothing',
      'kids clothing': 'Kids Clothing',
      'toys': 'Toys & Games',
      'baby care': 'Baby Care',
      'maternity': 'Maternity',
      'strollers': 'Strollers & Car Seats',
      'feeding': 'Feeding & Nursing',
      'safety': 'Safety & Security',
    },
    'Home & Furniture': {
      'furniture': 'Living Room Furniture',
      'bedding': 'Textiles & Soft Furnishing',
      'decor': 'Home Decor',
      'kitchen': 'Kitchen & Dining',
      'bathroom': 'Bathroom',
      'lighting': 'Lighting',
      'storage': 'Storage & Organization',
    },
    'Beauty & Personal Care': {
      'skincare': 'Skincare',
      'makeup': 'Makeup',
      'haircare': 'Haircare',
      'fragrances': 'Fragrances',
      'personal care': 'Personal Hygiene',
      'nail care': 'Nail Care',
      'body care': 'Body Care',
    },
    'Bags & Luggage': {
      'handbags': 'Handbags',
      'backpacks': 'Backpacks',
      'luggage': 'Travel Luggage',
      'briefcases': 'Briefcases & Business Bags',
      'sport bags': 'Sports & Gym Bags',
      'wallets': 'Wallets & Small Accessories',
    },
    'Electronics': {
      'smartphones': 'Smartphones & Accessories',
      'computers': 'Computers & Laptops',
      'tvs': 'TVs & Home Entertainment',
      'audio': 'Audio Equipment',
      'gaming': 'Gaming',
      'smart home': 'Smart Home & IoT',
      'cameras': 'Cameras & Photography',
      'wearables': 'Wearable Tech',
      'appliances': 'Home Appliances',
    },
    'Flowers & Gifts': {
      'bouquet': 'Bouquets & Arrangements',
      'arrangement': 'Bouquets & Arrangements',
      'plant': 'Potted Plants',
      'potted': 'Potted Plants',
      'chocolate': 'Gift Arrangements',
      'gift': 'Gift Arrangements',
      'vase': 'Flower Accessories',
      'pot': 'Flower Accessories',
      'wreath': 'Wreaths & Centerpieces',
      'centerpiece': 'Wreaths & Centerpieces',
    },
    'Sports & Outdoor': {
      'fitness': 'Fitness & Exercise',
      'sports': 'Sports',
      'water sports': 'Water Sports',
      'outdoor': 'Outdoor & Camping',
      'winter sports': 'Winter Sports',
      'cycling': 'Cycling',
      'running': 'Running & Athletics',
    },
    'Books, Stationery & Hobby': {
      'books': 'Books & Literature',
      'office supplies': 'Office & School Supplies',
      'art supplies': 'Art & Craft Supplies',
      'writing': 'Writing Instruments',
      'paper': 'Paper Products',
      'educational': 'Educational Materials',
      'hobbies': 'Hobbies & Collections',
    },
    'Tools & Hardware': {
      'hand tools': 'Hand Tools',
      'power tools': 'Power Tools',
      'hardware': 'Hardware & Fasteners',
      'electrical': 'Electrical Supplies',
      'plumbing': 'Plumbing Supplies',
      'safety': 'Safety Equipment',
      'measuring': 'Measuring Tools',
    },
    'Pet Supplies': {
      'dog': 'Dog Supplies',
      'cat': 'Cat Supplies',
      'bird': 'Bird Supplies',
      'fish': 'Fish & Aquarium',
      'small animals': 'Small Animal Supplies',
      'pet food': 'Pet Food & Treats',
      'pet care': 'Pet Care & Health',
    },
    'Automotive': {
      'car parts': 'Car Parts & Components',
      'car electronics': 'Car Electronics',
      'car care': 'Car Care & Maintenance',
      'tires': 'Tires & Wheels',
      'interior': 'Interior Accessories',
      'exterior': 'Exterior Accessories',
    },
    'Health & Wellness': {
      'vitamins': 'Vitamins & Supplements',
      'medical': 'Medical Equipment',
      'first aid': 'First Aid & Safety',
      'fitness': 'Fitness & Exercise Equipment',
      'health monitoring': 'Health Monitoring',
      'mobility': 'Mobility & Daily Living',
    },
  };

  // ------------------------------------------------------
  // 6) Additional Raw Data: Fashion Specific Fields
  // ------------------------------------------------------
  static String localizeFantasyWearType(String type, AppLocalizations l10n) {
    switch (type) {
      case 'Lingerie':
        return l10n.fantasyWearLingerie;
      case 'Babydoll':
        return l10n.fantasyWearBabydoll;
      case 'Chemise':
        return l10n.fantasyWearChemise;
      case 'Teddy':
        return l10n.fantasyWearTeddy;
      case 'Bodysuit':
        return l10n.fantasyWearBodysuit;
      case 'Corset':
        return l10n.fantasyWearCorset;
      case 'Bustier':
        return l10n.fantasyWearBustier;
      case 'Garter':
        return l10n.fantasyWearGarter;
      case 'Robe':
        return l10n.fantasyWearRobe;
      case 'Kimono':
        return l10n.fantasyWearKimono;
      case 'Costume':
        return l10n.fantasyWearCostume;
      case 'RolePlay':
        return l10n.fantasyWearRolePlay;
      case 'Sleepwear':
        return l10n.fantasyWearSleepwear;
      case 'Other':
        return l10n.fantasyWearOther;
      default:
        return type;
    }
  }

  static const List<String> kClothingGenders = [
    'Men',
    'Women',
    'Kids',
    'Unisex',
  ];

  static const List<String> kClothingSizes = [
    'XXS',
    'XS',
    'S',
    'M',
    'L',
    'XL',
    'XXL',
    '3XL',
    '4XL',
  ];

  static const List<String> kClothingFits = [
    'Slim',
    'Regular',
    'Loose',
    'Oversized',
  ];

  static const List<String> kClothingTypes = [
  'Cotton',
  'Polyester',
  'Wool',
  'Silk',
  'Denim',
  'Leather',
  'Linen',
  'Nylon',
  'Viscose',
  'Lycra',
  'Modal',
  'Lyocell',
  'Cashmere',
  'Chiffon',
  'Organic Cotton',
  'Recycled Cotton',
  'Canvas',
  'Jersey',
  'Gabardine',
  'Satin',
  'Rayon',
  'Elastane',  
  'Bamboo',
  'Velvet',
  'Fleece',
  'Spandex',
  'Tweed',
  'Corduroy',
  'Chino',
];

  // ------------------------------------------------------
  // 7) Helpers for Localization of Additional Fields
  // ------------------------------------------------------
  static String localizeClothingGender(
      String rawGender, AppLocalizations l10n) {
    switch (rawGender) {
      case 'Men':
        return l10n.clothingGenderMen;
      case 'Women':
        return l10n.clothingGenderWomen;
      case 'Kids':
        return l10n.clothingGenderKids;
      case 'Unisex':
        return l10n.clothingGenderUnisex;
      default:
        return rawGender;
    }
  }

  static String localizeClothingSize(String rawSize, AppLocalizations l10n) {
    switch (rawSize) {
      case 'XXS':
        return l10n.clothingSizeXXS;
      case 'XS':
        return l10n.clothingSizeXS;
      case 'S':
        return l10n.clothingSizeS;
      case 'M':
        return l10n.clothingSizeM;
      case 'L':
        return l10n.clothingSizeL;
      case 'XL':
        return l10n.clothingSizeXL;
      case 'XXL':
        return l10n.clothingSizeXXL;
      case '3XL':
        return l10n.clothingSize3XL;
      case '4XL':
        return l10n.clothingSize4XL;
      default:
        return rawSize;
    }
  }

  static String localizeFootwearGender(String gender, AppLocalizations l10n) {
    switch (gender) {
      case 'Woman':
        return l10n.footwearGenderWoman;
      case 'Man':
        return l10n.footwearGenderMan;
      case 'Kid':
        return l10n.footwearGenderKid;
      default:
        return gender;
    }
  }

  static String localizeClothingFit(String rawFit, AppLocalizations l10n) {
    switch (rawFit) {
      case 'Slim':
        return l10n.clothingFitSlim;
      case 'Regular':
        return l10n.clothingFitRegular;
      case 'Loose':
        return l10n.clothingFitLoose;
      case 'Oversized':
        return l10n.clothingFitOversized;
      default:
        return rawFit;
    }
  }

 static String localizeClothingType(String rawType, AppLocalizations l10n) {
  switch (rawType) {
    case 'Cotton':
      return l10n.clothingTypeCotton;
    case 'Polyester':
      return l10n.clothingTypePolyester;
    case 'Wool':
      return l10n.clothingTypeWool;
    case 'Silk':
      return l10n.clothingTypeSilk;
    case 'Denim':
      return l10n.clothingTypeDenim;
    case 'Leather':
      return l10n.clothingTypeLeather;
    case 'Linen':
      return l10n.clothingTypeLinen;
    case 'Nylon':
      return l10n.clothingTypeNylon;
    case 'Viscose':
      return l10n.clothingTypeViscose;
    case 'Modal':
      return l10n.clothingTypeModal;
    case 'Lyocell':
      return l10n.clothingTypeLyocell;
    case 'Lycra':
      return l10n.clothingTypeLycra;
    case 'Cashmere':
      return l10n.clothingTypeCashmere;
    case 'Chiffon':
      return l10n.clothingTypeChiffon;
    case 'Organic Cotton':
      return l10n.clothingTypeOrganicCotton;
    case 'Recycled Cotton':
      return l10n.clothingTypeRecycledCotton;
    case 'Canvas':
      return l10n.clothingTypeCanvas;
    case 'Jersey':
      return l10n.clothingTypeJersey;
    case 'Gabardine':
      return l10n.clothingTypeGabardine;
    case 'Satin':
      return l10n.clothingTypeSatin;
    case 'Rayon':
      return l10n.clothingTypeRayon;
    case 'Elastane':
      return l10n.clothingTypeElastane;  
    case 'Bamboo':
      return l10n.clothingTypeBamboo;
    case 'Velvet':
      return l10n.clothingTypeVelvet;
    case 'Fleece':
      return l10n.clothingTypeFleece;
    case 'Spandex':
      return l10n.clothingTypeSpandex;
    case 'Tweed':
      return l10n.clothingTypeTweed;
    case 'Corduroy':
      return l10n.clothingTypeCorduroy;
    case 'Chino':
      return l10n.clothingTypeChino;
    default:
      return rawType;
  }
}

  // ------------------------------------------------------
  // 8) Helpers for Localization of Categories, Subcategories, and Sub-subcategories
  // ------------------------------------------------------
  static String localizeCategoryKey(String rawKey, AppLocalizations l10n) {
    switch (rawKey) {
      case 'Clothing & Fashion':
        return l10n.categoryClothingFashion ?? 'Clothing & Fashion';
      case 'Footwear':
        return l10n.categoryFootwear ?? 'Footwear';
      case 'Accessories':
        return l10n.categoryAccessories ?? 'Accessories';
      case 'Mother & Child':
        return l10n.categoryMotherChild;
      case 'Home & Furniture':
        return l10n.categoryHomeFurniture;
      case 'Beauty & Personal Care':
        return l10n.categoryBeautyPersonalCare ?? 'Beauty & Personal Care';
      case 'Bags & Luggage':
        return l10n.categoryBagsLuggage ?? 'Bags & Luggage';
      case 'Electronics':
        return l10n.categoryElectronics;
      case 'Flowers & Gifts':
        return l10n.categoryFlowersGifts;
      case 'Sports & Outdoor':
        return l10n.categorySportsOutdoor;
      case 'Books, Stationery & Hobby':
        return l10n.categoryBooksStationeryHobby;
      case 'Tools & Hardware':
        return l10n.categoryToolsHardware;
      case 'Pet Supplies':
        return l10n.categoryPetSupplies;
      case 'Automotive':
        return l10n.categoryAutomotive ?? 'Automotive';
      case 'Health & Wellness':
        return l10n.categoryHealthWellness ?? 'Health & Wellness';
      default:
        return rawKey;
    }
  }

  static String localizeSubcategoryKey(
    String parentCategoryKey,
    String subKey,
    AppLocalizations l10n,
  ) {
    switch (parentCategoryKey) {
      case 'Clothing & Fashion':
        switch (subKey) {
          case 'Dresses':
            return l10n.subcategoryDresses ?? 'Dresses';
          case 'Tops & Shirts':
            return l10n.subcategoryTopsShirts ?? 'Tops & Shirts';
          case 'Bottoms':
            return l10n.subcategoryBottoms ?? 'Bottoms';
          case 'Outerwear':
            return l10n.subcategoryOuterwear ?? 'Outerwear';
          case 'Underwear & Sleepwear':
            return l10n.subcategoryUnderwearSleepwear ??
                'Underwear & Sleepwear';
          case 'Swimwear':
            return l10n.subcategorySwimwear ?? 'Swimwear';
          case 'Activewear':
            return l10n.subcategoryActivewear ?? 'Activewear';
          case 'Suits & Formal':
            return l10n.subcategorySuitsFormal ?? 'Suits & Formal';
          case 'Traditional & Cultural':
            return l10n.subcategoryTraditionalCultural ??
                'Traditional & Cultural';
        }
        break;
      case 'Footwear':
        switch (subKey) {
          case 'Sneakers & Athletic':
            return l10n.subcategorySneakersAthletic ?? 'Sneakers & Athletic';
          case 'Casual Shoes':
            return l10n.subcategoryCasualShoes ?? 'Casual Shoes';
          case 'Formal Shoes':
            return l10n.subcategoryFormalShoes ?? 'Formal Shoes';
          case 'Boots':
            return l10n.subcategoryBoots ?? 'Boots';
          case 'Sandals & Flip-Flops':
            return l10n.subcategorySandalsFlipFlops ?? 'Sandals & Flip-Flops';
          case 'Slippers':
            return l10n.subcategorySlippers ?? 'Slippers';
          case 'Specialized Footwear':
            return l10n.subcategorySpecializedFootwear ??
                'Specialized Footwear';
        }
        break;
      case 'Accessories':
        switch (subKey) {
          case 'Jewelry':
            return l10n.subcategoryJewelry ?? 'Jewelry';
          case 'Watches':
            return l10n.subcategoryWatches ?? 'Watches';
          case 'Belts':
            return l10n.subcategoryBelts ?? 'Belts';
          case 'Hats & Caps':
            return l10n.subcategoryHatsCaps ?? 'Hats & Caps';
          case 'Scarves & Wraps':
            return l10n.subcategoryScarvesWraps ?? 'Scarves & Wraps';
          case 'Sunglasses & Eyewear':
            return l10n.subcategorySunglassesEyewear ?? 'Sunglasses & Eyewear';
          case 'Gloves':
            return l10n.subcategoryGloves ?? 'Gloves';
          case 'Hair Accessories':
            return l10n.subcategoryHairAccessories ?? 'Hair Accessories';
          case 'Other Accessories':
            return l10n.subcategoryOtherAccessories ?? 'Other Accessories';
        }
        break;
      case 'Mother & Child':
        switch (subKey) {
          case 'Baby Clothing':
            return l10n.subcategoryBabyClothing ?? 'Baby Clothing';
          case 'Kids Clothing':
            return l10n.subcategoryKidsClothing ?? 'Kids Clothing';
          case 'Kids Footwear':
            return l10n.subcategoryKidsFootwear ?? 'Kids Footwear';
          case 'Toys & Games':
            return l10n.subcategoryToysGames ?? 'Toys & Games';
          case 'Baby Care':
            return l10n.subcategoryBabyCare ?? 'Baby Care';
          case 'Maternity':
            return l10n.subcategoryMaternity ?? 'Maternity';
          case 'Strollers & Car Seats':
            return l10n.subcategoryStrollersCarSeats ?? 'Strollers & Car Seats';
          case 'Feeding & Nursing':
            return l10n.subcategoryFeedingNursing ?? 'Feeding & Nursing';
          case 'Safety & Security':
            return l10n.subcategorySafetySecurity ?? 'Safety & Security';
          case 'Educational':
            return l10n.subcategoryEducational ?? 'Educational';
        }
        break;
      case 'Home & Furniture':
        switch (subKey) {
          case 'Living Room Furniture':
            return l10n.subcategoryLivingRoomFurniture ??
                'Living Room Furniture';
          case 'Bedroom Furniture':
            return l10n.subcategoryBedroomFurniture ?? 'Bedroom Furniture';
          case 'Kitchen & Dining':
            return l10n.subcategoryKitchenDining ?? 'Kitchen & Dining';
          case 'Bathroom':
            return l10n.subcategoryBathroom ?? 'Bathroom';
          case 'Home Decor':
            return l10n.subcategoryHomeDecor ?? 'Home Decor';
          case 'Lighting':
            return l10n.subcategoryLighting ?? 'Lighting';
          case 'Storage & Organization':
            return l10n.subcategoryStorageOrganization ??
                'Storage & Organization';
          case 'Textiles & Soft Furnishing':
            return l10n.subcategoryTextilesSoftFurnishing ??
                'Textiles & Soft Furnishing';
          case 'Garden & Outdoor':
            return l10n.subcategoryGardenOutdoor ?? 'Garden & Outdoor';
        }
        break;
      case 'Beauty & Personal Care':
        switch (subKey) {
          case 'Skincare':
            return l10n.subcategorySkincare ?? 'Skincare';
          case 'Makeup':
            return l10n.subcategoryMakeup ?? 'Makeup';
          case 'Haircare':
            return l10n.subcategoryHaircare ?? 'Haircare';
          case 'Fragrances':
            return l10n.subcategoryFragrances ?? 'Fragrances';
          case 'Personal Hygiene':
            return l10n.subcategoryPersonalHygiene ?? 'Personal Hygiene';
          case 'Nail Care':
            return l10n.subcategoryNailCare ?? 'Nail Care';
          case 'Body Care':
            return l10n.subcategoryBodyCare ?? 'Body Care';
          case 'Oral Care':
            return l10n.subcategoryOralCare ?? 'Oral Care';
          case 'Beauty Tools & Accessories':
            return l10n.subcategoryBeautyToolsAccessories ??
                'Beauty Tools & Accessories';
        }
        break;
      case 'Bags & Luggage':
        switch (subKey) {
          case 'Handbags':
            return l10n.subcategoryHandbags ?? 'Handbags';
          case 'Backpacks':
            return l10n.subcategoryBackpacks ?? 'Backpacks';
          case 'Travel Luggage':
            return l10n.subcategoryTravelLuggage ?? 'Travel Luggage';
          case 'Briefcases & Business Bags':
            return l10n.subcategoryBriefcasesBusinessBags ??
                'Briefcases & Business Bags';
          case 'Sports & Gym Bags':
            return l10n.subcategorySportsGymBags ?? 'Sports & Gym Bags';
          case 'Wallets & Small Accessories':
            return l10n.subcategoryWalletsSmallAccessories ??
                'Wallets & Small Accessories';
          case 'Specialty Bags':
            return l10n.subcategorySpecialtyBags ?? 'Specialty Bags';
        }
        break;
      case 'Electronics':
        switch (subKey) {
          case 'Smartphones & Accessories':
            return l10n.subcategorySmartphonesAccessories ??
                'Smartphones & Accessories';
          case 'Computers & Laptops':
            return l10n.subcategoryComputersLaptops ?? 'Computers & Laptops';
          case 'TVs & Home Entertainment':
            return l10n.subcategoryTVsHomeEntertainment ??
                'TVs & Home Entertainment';
          case 'Audio Equipment':
            return l10n.subcategoryAudioEquipment ?? 'Audio Equipment';
          case 'Gaming':
            return l10n.subcategoryGaming ?? 'Gaming';
          case 'Smart Home & IoT':
            return l10n.subcategorySmartHomeIoT ?? 'Smart Home & IoT';
          case 'Cameras & Photography':
            return l10n.subcategoryCamerasPhotography ??
                'Cameras & Photography';
          case 'Wearable Tech':
            return l10n.subcategoryWearableTech ?? 'Wearable Tech';
          case 'Home Appliances':
            return l10n.subcategoryHomeAppliances ?? 'Home Appliances';
          case 'Personal Care Electronics':
            return l10n.subcategoryPersonalCareElectronics ??
                'Personal Care Electronics';
        }
        break;
      case 'Flowers & Gifts':
        switch (subKey) {
          case 'Bouquets & Arrangements':
            return l10n.subcategoryBouquetsArrangements ??
                'Bouquets & Arrangements';
          case 'Potted Plants':
            return l10n.subcategoryPottedPlants ?? 'Potted Plants';
          case 'Gift Arrangements':
            return l10n.subcategoryGiftArrangements ?? 'Gift Arrangements';
          case 'Flower Accessories':
            return l10n.subcategoryFlowerAccessories ?? 'Flower Accessories';
          case 'Wreaths & Centerpieces':
            return l10n.subcategoryWreathsCenterpieces ??
                'Wreaths & Centerpieces';
        }
        break;
      case 'Sports & Outdoor':
        switch (subKey) {
          case 'Fitness & Exercise':
            return l10n.subcategoryFitnessExercise ?? 'Fitness & Exercise';
          case 'Sports':
            return l10n.subcategorySports ?? 'Sports';
          case 'Water Sports':
            return l10n.subcategoryWaterSports ?? 'Water Sports';
          case 'Outdoor & Camping':
            return l10n.subcategoryOutdoorCamping ?? 'Outdoor & Camping';
          case 'Winter Sports':
            return l10n.subcategoryWinterSports ?? 'Winter Sports';
          case 'Cycling':
            return l10n.subcategoryCycling ?? 'Cycling';
          case 'Running & Athletics':
            return l10n.subcategoryRunningAthletics ?? 'Running & Athletics';
          case 'Sports Accessories':
            return l10n.subcategorySportsAccessories ?? 'Sports Accessories';
          case 'Sportswear':
            return l10n.subcategorySportswear ?? 'Sportswear';
        }
        break;
      case 'Books, Stationery & Hobby':
        switch (subKey) {
          case 'Books & Literature':
            return l10n.subcategoryBooksLiterature ?? 'Books & Literature';
          case 'Office & School Supplies':
            return l10n.subcategoryOfficeSchoolSupplies ??
                'Office & School Supplies';
          case 'Art & Craft Supplies':
            return l10n.subcategoryArtCraftSupplies ?? 'Art & Craft Supplies';
          case 'Writing Instruments':
            return l10n.subcategoryWritingInstruments ?? 'Writing Instruments';
          case 'Paper Products':
            return l10n.subcategoryPaperProducts ?? 'Paper Products';
          case 'Educational Materials':
            return l10n.subcategoryEducationalMaterials ??
                'Educational Materials';
          case 'Hobbies & Collections':
            return l10n.subcategoryHobbiesCollections ??
                'Hobbies & Collections';
          case 'Musical Instruments':
            return l10n.subcategoryMusicalInstruments ?? 'Musical Instruments';
        }
        break;
      case 'Tools & Hardware':
        switch (subKey) {
          case 'Hand Tools':
            return l10n.subcategoryHandTools ?? 'Hand Tools';
          case 'Power Tools':
            return l10n.subcategoryPowerTools ?? 'Power Tools';
          case 'Hardware & Fasteners':
            return l10n.subcategoryHardwareFasteners ?? 'Hardware & Fasteners';
          case 'Electrical Supplies':
            return l10n.subcategoryElectricalSupplies ?? 'Electrical Supplies';
          case 'Plumbing Supplies':
            return l10n.subcategoryPlumbingSupplies ?? 'Plumbing Supplies';
          case 'Building Materials':
            return l10n.subcategoryBuildingMaterials ?? 'Building Materials';
          case 'Safety Equipment':
            return l10n.subcategorySafetyEquipment ?? 'Safety Equipment';
          case 'Measuring Tools':
            return l10n.subcategoryMeasuringTools ?? 'Measuring Tools';
          case 'Tool Storage':
            return l10n.subcategoryToolStorage ?? 'Tool Storage';
        }
        break;
      case 'Pet Supplies':
        switch (subKey) {
          case 'Dog Supplies':
            return l10n.subcategoryDogSupplies ?? 'Dog Supplies';
          case 'Cat Supplies':
            return l10n.subcategoryCatSupplies ?? 'Cat Supplies';
          case 'Bird Supplies':
            return l10n.subcategoryBirdSupplies ?? 'Bird Supplies';
          case 'Fish & Aquarium':
            return l10n.subcategoryFishAquarium ?? 'Fish & Aquarium';
          case 'Small Animal Supplies':
            return l10n.subcategorySmallAnimalSupplies ??
                'Small Animal Supplies';
          case 'Pet Food & Treats':
            return l10n.subcategoryPetFoodTreats ?? 'Pet Food & Treats';
          case 'Pet Care & Health':
            return l10n.subcategoryPetCareHealth ?? 'Pet Care & Health';
          case 'Pet Accessories':
            return l10n.subcategoryPetAccessories ?? 'Pet Accessories';
          case 'Pet Training':
            return l10n.subcategoryPetTraining ?? 'Pet Training';
        }
        break;
      case 'Automotive':
        switch (subKey) {
          case 'Car Parts & Components':
            return l10n.subcategoryCarPartsComponents ??
                'Car Parts & Components';
          case 'Car Electronics':
            return l10n.subcategoryCarElectronics ?? 'Car Electronics';
          case 'Car Care & Maintenance':
            return l10n.subcategoryCarCareMaintenance ??
                'Car Care & Maintenance';
          case 'Tires & Wheels':
            return l10n.subcategoryTiresWheels ?? 'Tires & Wheels';
          case 'Interior Accessories':
            return l10n.subcategoryInteriorAccessories ??
                'Interior Accessories';
          case 'Exterior Accessories':
            return l10n.subcategoryExteriorAccessories ??
                'Exterior Accessories';
          case 'Tools & Equipment':
            return l10n.subcategoryToolsEquipment ?? 'Tools & Equipment';
          case 'Motorcycle Parts':
            return l10n.subcategoryMotorcycleParts ?? 'Motorcycle Parts';
        }
        break;
      case 'Health & Wellness':
        switch (subKey) {
          case 'Vitamins & Supplements':
            return l10n.subcategoryVitaminsSupplements ??
                'Vitamins & Supplements';
          case 'Medical Equipment':
            return l10n.subcategoryMedicalEquipment ?? 'Medical Equipment';
          case 'First Aid & Safety':
            return l10n.subcategoryFirstAidSafety ?? 'First Aid & Safety';
          case 'Fitness & Exercise Equipment':
            return l10n.subcategoryFitnessExerciseEquipment ??
                'Fitness & Exercise Equipment';
          case 'Health Monitoring':
            return l10n.subcategoryHealthMonitoring ?? 'Health Monitoring';
          case 'Mobility & Daily Living':
            return l10n.subcategoryMobilityDailyLiving ??
                'Mobility & Daily Living';
          case 'Alternative Medicine':
            return l10n.subcategoryAlternativeMedicine ??
                'Alternative Medicine';
          case 'Personal Care':
            return l10n.subcategoryPersonalCare ?? 'Personal Care';
        }
        break;
    }
    return subKey;
  }

  static String localizeSubSubcategoryKey(
    String parentCategoryKey,
    String parentSubcategoryKey,
    String subSubKey,
    AppLocalizations l10n,
  ) {
    switch (parentCategoryKey) {
      case 'Clothing & Fashion':
        switch (parentSubcategoryKey) {
          case 'Dresses':
            switch (subSubKey) {
              case 'Casual Dresses':
                return l10n.subSubcategoryCasualDresses ?? 'Casual Dresses';
              case 'Formal Dresses':
                return l10n.subSubcategoryFormalDresses ?? 'Formal Dresses';
              case 'Evening Gowns':
                return l10n.subSubcategoryEveningGowns ?? 'Evening Gowns';
              case 'Cocktail Dresses':
                return l10n.subSubcategoryCocktailDresses ?? 'Cocktail Dresses';
              case 'Maxi Dresses':
                return l10n.subSubcategoryMaxiDresses ?? 'Maxi Dresses';
              case 'Mini Dresses':
                return l10n.subSubcategoryMiniDresses ?? 'Mini Dresses';
              case 'Midi Dresses':
                return l10n.subSubcategoryMidiDresses ?? 'Midi Dresses';
              case 'Wedding Dresses':
                return l10n.subSubcategoryWeddingDresses ?? 'Wedding Dresses';
              case 'Sundresses':
                return l10n.subSubcategorySundresses ?? 'Sundresses';
            }
            break;
          case 'Tops & Shirts':
            switch (subSubKey) {
              case 'T-Shirts':
                return l10n.subSubcategoryTShirts ?? 'T-Shirts';
              case 'Shirts':
                return l10n.subSubcategoryShirts ?? 'Shirts';
              case 'Blouses':
                return l10n.subSubcategoryBlouses ?? 'Blouses';
              case 'Tank Tops':
                return l10n.subSubcategoryTankTops ?? 'Tank Tops';
              case 'Polo Shirts':
                return l10n.subSubcategoryPoloShirts ?? 'Polo Shirts';
              case 'Crop Tops':
                return l10n.subSubcategoryCropTops ?? 'Crop Tops';
              case 'Tunics':
                return l10n.subSubcategoryTunics ?? 'Tunics';
              case 'Hoodies':
                return l10n.subSubcategoryHoodies ?? 'Hoodies';
              case 'Sweatshirts':
                return l10n.subSubcategorySweatshirts ?? 'Sweatshirts';
            }
            break;
          case 'Bottoms':
            switch (subSubKey) {
              case 'Jeans':
                return l10n.subSubcategoryJeans ?? 'Jeans';
              case 'Pants':
                return l10n.subSubcategoryPants ?? 'Pants';
              case 'Shorts':
                return l10n.subSubcategoryShorts ?? 'Shorts';
              case 'Skirts':
                return l10n.subSubcategorySkirts ?? 'Skirts';
              case 'Leggings':
                return l10n.subSubcategoryLeggings ?? 'Leggings';
              case 'Joggers':
                return l10n.subSubcategoryJoggers ?? 'Joggers';
              case 'Capris':
                return l10n.subSubcategoryCapris ?? 'Capris';
              case 'Culottes':
                return l10n.subSubcategoryCulottes ?? 'Culottes';
            }
            break;
          case 'Outerwear':
            switch (subSubKey) {
              case 'Jackets':
                return l10n.subSubcategoryJackets ?? 'Jackets';
              case 'Coats':
                return l10n.subSubcategoryCoats ?? 'Coats';
              case 'Blazers':
                return l10n.subSubcategoryBlazers ?? 'Blazers';
              case 'Cardigans':
                return l10n.subSubcategoryCardigans ?? 'Cardigans';
              case 'Sweaters':
                return l10n.subSubcategorySweaters ?? 'Sweaters';
              case 'Vests':
                return l10n.subSubcategoryVests ?? 'Vests';
              case 'Parkas':
                return l10n.subSubcategoryParkas ?? 'Parkas';
              case 'Trench Coats':
                return l10n.subSubcategoryTrenchCoats ?? 'Trench Coats';
              case 'Windbreakers':
                return l10n.subSubcategoryWindbreakers ?? 'Windbreakers';
            }
            break;
          case 'Underwear & Sleepwear':
            switch (subSubKey) {
              case 'Bras':
                return l10n.subSubcategoryBras ?? 'Bras';
              case 'Panties':
                return l10n.subSubcategoryPanties ?? 'Panties';
              case 'Boxers':
                return l10n.subSubcategoryBoxers ?? 'Boxers';
              case 'Briefs':
                return l10n.subSubcategoryBriefs ?? 'Briefs';
              case 'Undershirts':
                return l10n.subSubcategoryUndershirts ?? 'Undershirts';
              case 'Sleepwear':
                return l10n.subSubcategorySleepwear ?? 'Sleepwear';
              case 'Pajamas':
                return l10n.subSubcategoryPajamas ?? 'Pajamas';
              case 'Nightgowns':
                return l10n.subSubcategoryNightgowns ?? 'Nightgowns';
              case 'Robes':
                return l10n.subSubcategoryRobes ?? 'Robes';
              case 'Socks':
                return l10n.subSubcategorySocks ?? 'Socks';
              case 'Tights':
                return l10n.subSubcategoryTights ?? 'Tights';
              case 'Fantasy':
                return l10n.subSubcategoryFantasy ?? 'Fantasy';
            }
            break;
          case 'Swimwear':
            switch (subSubKey) {
              case 'Bikinis':
                return l10n.subSubcategoryBikinis ?? 'Bikinis';
              case 'One-Piece Swimsuits':
                return l10n.subSubcategoryOnePieceSwimsuits ??
                    'One-Piece Swimsuits';
              case 'Swim Shorts':
                return l10n.subSubcategorySwimShorts ?? 'Swim Shorts';
              case 'Boardshorts':
                return l10n.subSubcategoryBoardshorts ?? 'Boardshorts';
              case 'Cover-Ups':
                return l10n.subSubcategoryCoverUps ?? 'Cover-Ups';
              case 'Rashguards':
                return l10n.subSubcategoryRashguards ?? 'Rashguards';
            }
            break;
          case 'Activewear':
            switch (subSubKey) {
              case 'Sports Bras':
                return l10n.subSubcategorySportsBras ?? 'Sports Bras';
              case 'Athletic Tops':
                return l10n.subSubcategoryAthleticTops ?? 'Athletic Tops';
              case 'Athletic Bottoms':
                return l10n.subSubcategoryAthleticBottoms ?? 'Athletic Bottoms';
              case 'Tracksuits':
                return l10n.subSubcategoryTracksuits ?? 'Tracksuits';
              case 'Yoga Wear':
                return l10n.subSubcategoryYogaWear ?? 'Yoga Wear';
              case 'Running Gear':
                return l10n.subSubcategoryRunningGear ?? 'Running Gear';
              case 'Gym Wear':
                return l10n.subSubcategoryGymWear ?? 'Gym Wear';
            }
            break;
          case 'Suits & Formal':
            switch (subSubKey) {
              case 'Business Suits':
                return l10n.subSubcategoryBusinessSuits ?? 'Business Suits';
              case 'Tuxedos':
                return l10n.subSubcategoryTuxedos ?? 'Tuxedos';
              case 'Formal Shirts':
                return l10n.subSubcategoryFormalShirts ?? 'Formal Shirts';
              case 'Dress Pants':
                return l10n.subSubcategoryDressPants ?? 'Dress Pants';
              case 'Waistcoats':
                return l10n.subSubcategoryWaistcoats ?? 'Waistcoats';
              case 'Bow Ties':
                return l10n.subSubcategoryBowTies ?? 'Bow Ties';
              case 'Cufflinks':
                return l10n.subSubcategoryCufflinks ?? 'Cufflinks';
            }
            break;
          case 'Traditional & Cultural':
            switch (subSubKey) {
              case 'Ethnic Wear':
                return l10n.subSubcategoryEthnicWear ?? 'Ethnic Wear';
              case 'Cultural Costumes':
                return l10n.subSubcategoryCulturalCostumes ??
                    'Cultural Costumes';
              case 'Traditional Dresses':
                return l10n.subSubcategoryTraditionalDresses ??
                    'Traditional Dresses';
              case 'Ceremonial Clothing':
                return l10n.subSubcategoryCeremonialClothing ??
                    'Ceremonial Clothing';
            }
            break;
        }
        break;
      case 'Footwear':
        switch (parentSubcategoryKey) {
          case 'Sneakers & Athletic':
            switch (subSubKey) {
              case 'Running Shoes':
                return l10n.subSubcategoryRunningShoes ?? 'Running Shoes';
              case 'Basketball Shoes':
                return l10n.subSubcategoryBasketballShoes ?? 'Basketball Shoes';
              case 'Training Shoes':
                return l10n.subSubcategoryTrainingShoes ?? 'Training Shoes';
              case 'Casual Sneakers':
                return l10n.subSubcategoryCasualSneakers ?? 'Casual Sneakers';
              case 'Skateboard Shoes':
                return l10n.subSubcategorySkateboardShoes ?? 'Skateboard Shoes';
              case 'Tennis Shoes':
                return l10n.subSubcategoryTennisShoes ?? 'Tennis Shoes';
              case 'Walking Shoes':
                return l10n.subSubcategoryWalkingShoes ?? 'Walking Shoes';
            }
            break;
          case 'Casual Shoes':
            switch (subSubKey) {
              case 'Loafers':
                return l10n.subSubcategoryLoafers ?? 'Loafers';
              case 'Boat Shoes':
                return l10n.subSubcategoryBoatShoes ?? 'Boat Shoes';
              case 'Canvas Shoes':
                return l10n.subSubcategoryCanvasShoes ?? 'Canvas Shoes';
              case 'Slip-On Shoes':
                return l10n.subSubcategorySlipOnShoes ?? 'Slip-On Shoes';
              case 'Espadrilles':
                return l10n.subSubcategoryEspadrilles ?? 'Espadrilles';
              case 'Moccasins':
                return l10n.subSubcategoryMoccasins ?? 'Moccasins';
            }
            break;
          case 'Formal Shoes':
            switch (subSubKey) {
              case 'Dress Shoes':
                return l10n.subSubcategoryDressShoes ?? 'Dress Shoes';
              case 'Oxford Shoes':
                return l10n.subSubcategoryOxfordShoes ?? 'Oxford Shoes';
              case 'Derby Shoes':
                return l10n.subSubcategoryDerbyShoes ?? 'Derby Shoes';
              case 'Monk Strap Shoes':
                return l10n.subSubcategoryMonkStrapShoes ?? 'Monk Strap Shoes';
              case 'Pumps':
                return l10n.subSubcategoryPumps ?? 'Pumps';
              case 'High Heels':
                return l10n.subSubcategoryHighHeels ?? 'High Heels';
              case 'Flats':
                return l10n.subSubcategoryFlats ?? 'Flats';
            }
            break;
          case 'Boots':
            switch (subSubKey) {
              case 'Ankle Boots':
                return l10n.subSubcategoryAnkleBoots ?? 'Ankle Boots';
              case 'Knee-High Boots':
                return l10n.subSubcategoryKneeHighBoots ?? 'Knee-High Boots';
              case 'Combat Boots':
                return l10n.subSubcategoryCombatBoots ?? 'Combat Boots';
              case 'Chelsea Boots':
                return l10n.subSubcategoryChelseaBoots ?? 'Chelsea Boots';
              case 'Work Boots':
                return l10n.subSubcategoryWorkBoots ?? 'Work Boots';
              case 'Hiking Boots':
                return l10n.subSubcategoryHikingBoots ?? 'Hiking Boots';
              case 'Rain Boots':
                return l10n.subSubcategoryRainBoots ?? 'Rain Boots';
              case 'Snow Boots':
                return l10n.subSubcategorySnowBoots ?? 'Snow Boots';
            }
            break;
          case 'Sandals & Flip-Flops':
            switch (subSubKey) {
              case 'Flip-Flops':
                return l10n.subSubcategoryFlipFlops ?? 'Flip-Flops';
              case 'Flat Sandals':
                return l10n.subSubcategoryFlatSandals ?? 'Flat Sandals';
              case 'Heeled Sandals':
                return l10n.subSubcategoryHeeledSandals ?? 'Heeled Sandals';
              case 'Sport Sandals':
                return l10n.subSubcategorySportSandals ?? 'Sport Sandals';
              case 'Slides':
                return l10n.subSubcategorySlides ?? 'Slides';
              case 'Gladiator Sandals':
                return l10n.subSubcategoryGladiatorSandals ??
                    'Gladiator Sandals';
            }
            break;
          case 'Slippers':
            switch (subSubKey) {
              case 'House Slippers':
                return l10n.subSubcategoryHouseSlippers ?? 'House Slippers';
              case 'Bedroom Slippers':
                return l10n.subSubcategoryBedroomSlippers ?? 'Bedroom Slippers';
              case 'Moccasin Slippers':
                return l10n.subSubcategoryMoccasinSlippers ??
                    'Moccasin Slippers';
              case 'Slipper Boots':
                return l10n.subSubcategorySlipperBoots ?? 'Slipper Boots';
            }
            break;
          case 'Specialized Footwear':
            switch (subSubKey) {
              case 'Safety Shoes':
                return l10n.subSubcategorySafetyShoes ?? 'Safety Shoes';
              case 'Medical Shoes':
                return l10n.subSubcategoryMedicalShoes ?? 'Medical Shoes';
              case 'Dance Shoes':
                return l10n.subSubcategoryDanceShoes ?? 'Dance Shoes';
              case 'Cleats':
                return l10n.subSubcategoryCleats ?? 'Cleats';
              case 'Climbing Shoes':
                return l10n.subSubcategoryClimbingShoes ?? 'Climbing Shoes';
            }
            break;
        }
        break;
      case 'Accessories':
        switch (parentSubcategoryKey) {
          case 'Jewelry':
            switch (subSubKey) {
              case 'Necklaces':
                return l10n.subSubcategoryNecklaces ?? 'Necklaces';
              case 'Earrings':
                return l10n.subSubcategoryEarrings ?? 'Earrings';
              case 'Rings':
                return l10n.subSubcategoryRings ?? 'Rings';
              case 'Bracelets':
                return l10n.subSubcategoryBracelets ?? 'Bracelets';
              case 'Anklets':
                return l10n.subSubcategoryAnklets ?? 'Anklets';
              case 'Brooches':
                return l10n.subSubcategoryBrooches ?? 'Brooches';
              case 'Jewelry Sets':
                return l10n.subSubcategoryJewelrySets ?? 'Jewelry Sets';
              case 'Body Jewelry':
                return l10n.subSubcategoryBodyJewelry ?? 'Body Jewelry';
            }
            break;
          case 'Watches':
            switch (subSubKey) {
              case 'Analog Watches':
                return l10n.subSubcategoryAnalogWatches ?? 'Analog Watches';
              case 'Digital Watches':
                return l10n.subSubcategoryDigitalWatches ?? 'Digital Watches';
              case 'Smartwatches':
                return l10n.subSubcategorySmartwatches ?? 'Smartwatches';
              case 'Sports Watches':
                return l10n.subSubcategorySportsWatches ?? 'Sports Watches';
              case 'Luxury Watches':
                return l10n.subSubcategoryLuxuryWatches ?? 'Luxury Watches';
              case 'Fashion Watches':
                return l10n.subSubcategoryFashionWatches ?? 'Fashion Watches';
              case 'Kids Watches':
                return l10n.subSubcategoryKidsWatches ?? 'Kids Watches';
            }
            break;
          case 'Belts':
            switch (subSubKey) {
              case 'Leather Belts':
                return l10n.subSubcategoryLeatherBelts ?? 'Leather Belts';
              case 'Fabric Belts':
                return l10n.subSubcategoryFabricBelts ?? 'Fabric Belts';
              case 'Chain Belts':
                return l10n.subSubcategoryChainBelts ?? 'Chain Belts';
              case 'Dress Belts':
                return l10n.subSubcategoryDressBelts ?? 'Dress Belts';
              case 'Casual Belts':
                return l10n.subSubcategoryCasualBelts ?? 'Casual Belts';
              case 'Designer Belts':
                return l10n.subSubcategoryDesignerBelts ?? 'Designer Belts';
            }
            break;
          case 'Hats & Caps':
            switch (subSubKey) {
              case 'Baseball Caps':
                return l10n.subSubcategoryBaseballCaps ?? 'Baseball Caps';
              case 'Beanies':
                return l10n.subSubcategoryBeanies ?? 'Beanies';
              case 'Fedoras':
                return l10n.subSubcategoryFedoras ?? 'Fedoras';
              case 'Sun Hats':
                return l10n.subSubcategorySunHats ?? 'Sun Hats';
              case 'Bucket Hats':
                return l10n.subSubcategoryBucketHats ?? 'Bucket Hats';
              case 'Berets':
                return l10n.subSubcategoryBerets ?? 'Berets';
              case 'Snapbacks':
                return l10n.subSubcategorySnapbacks ?? 'Snapbacks';
            }
            break;
          case 'Scarves & Wraps':
            switch (subSubKey) {
              case 'Silk Scarves':
                return l10n.subSubcategorySilkScarves ?? 'Silk Scarves';
              case 'Winter Scarves':
                return l10n.subSubcategoryWinterScarves ?? 'Winter Scarves';
              case 'Shawls':
                return l10n.subSubcategoryShawls ?? 'Shawls';
              case 'Pashminas':
                return l10n.subSubcategoryPashminas ?? 'Pashminas';
              case 'Bandanas':
                return l10n.subSubcategoryBandanas ?? 'Bandanas';
              case 'Wraps':
                return l10n.subSubcategoryWraps ?? 'Wraps';
            }
            break;
          case 'Sunglasses & Eyewear':
            switch (subSubKey) {
              case 'Sunglasses':
                return l10n.subSubcategorySunglasses ?? 'Sunglasses';
              case 'Reading Glasses':
                return l10n.subSubcategoryReadingGlasses ?? 'Reading Glasses';
              case 'Blue Light Glasses':
                return l10n.subSubcategoryBlueLightGlasses ??
                    'Blue Light Glasses';
              case 'Safety Glasses':
                return l10n.subSubcategorySafetyGlasses ?? 'Safety Glasses';
              case 'Fashion Glasses':
                return l10n.subSubcategoryFashionGlasses ?? 'Fashion Glasses';
            }
            break;
          case 'Gloves':
            switch (subSubKey) {
              case 'Winter Gloves':
                return l10n.subSubcategoryWinterGloves ?? 'Winter Gloves';
              case 'Dress Gloves':
                return l10n.subSubcategoryDressGloves ?? 'Dress Gloves';
              case 'Work Gloves':
                return l10n.subSubcategoryWorkGloves ?? 'Work Gloves';
              case 'Sports Gloves':
                return l10n.subSubcategorySportsGloves ?? 'Sports Gloves';
              case 'Touchscreen Gloves':
                return l10n.subSubcategoryTouchscreenGloves ??
                    'Touchscreen Gloves';
            }
            break;
          case 'Hair Accessories':
            switch (subSubKey) {
              case 'Hair Clips':
                return l10n.subSubcategoryHairClips ?? 'Hair Clips';
              case 'Headbands':
                return l10n.subSubcategoryHeadbands ?? 'Headbands';
              case 'Hair Ties':
                return l10n.subSubcategoryHairTies ?? 'Hair Ties';
              case 'Bobby Pins':
                return l10n.subSubcategoryBobbyPins ?? 'Bobby Pins';
              case 'Hair Scarves':
                return l10n.subSubcategoryHairScarves ?? 'Hair Scarves';
              case 'Hair Jewelry':
                return l10n.subSubcategoryHairJewelry ?? 'Hair Jewelry';
            }
            break;
          case 'Other Accessories':
            switch (subSubKey) {
              case 'Keychains':
                return l10n.subSubcategoryKeychains ?? 'Keychains';
              case 'Phone Cases':
                return l10n.subSubcategoryPhoneCases ?? 'Phone Cases';
              case 'Wallets':
                return l10n.subSubcategoryWallets ?? 'Wallets';
              case 'Purse Accessories':
                return l10n.subSubcategoryPurseAccessories ??
                    'Purse Accessories';
              case 'Pins & Badges':
                return l10n.subSubcategoryPinsBadges ?? 'Pins & Badges';
            }
            break;
        }
        break;
      case 'Mother & Child':
        switch (parentSubcategoryKey) {
          case 'Baby Clothing':
            switch (subSubKey) {
              case 'Bodysuits':
                return l10n.subSubcategoryBodysuits ?? 'Bodysuits';
              case 'Rompers':
                return l10n.subSubcategoryRompers ?? 'Rompers';
              case 'Baby Sets':
                return l10n.subSubcategoryBabySets ?? 'Baby Sets';
              case 'Baby Sleepwear':
                return l10n.subSubcategoryBabySleepwear ?? 'Baby Sleepwear';
              case 'Baby Socks':
                return l10n.subSubcategoryBabySocks ?? 'Baby Socks';
              case 'Baby Hats':
                return l10n.subSubcategoryBabyHats ?? 'Baby Hats';
              case 'Baby Mittens':
                return l10n.subSubcategoryBabyMittens ?? 'Baby Mittens';
            }
            break;
          case 'Kids Clothing':
            switch (subSubKey) {
              case 'Kids T-Shirts':
                return l10n.subSubcategoryKidsTShirts ?? 'Kids T-Shirts';
              case 'Kids Pants':
                return l10n.subSubcategoryKidsPants ?? 'Kids Pants';
              case 'Kids Dresses':
                return l10n.subSubcategoryKidsDresses ?? 'Kids Dresses';
              case 'Kids Sweatshirts':
                return l10n.subSubcategoryKidsSweatshirts ?? 'Kids Sweatshirts';
              case 'Kids Jackets':
                return l10n.subSubcategoryKidsJackets ?? 'Kids Jackets';
              case 'Kids Pajamas':
                return l10n.subSubcategoryKidsPajamas ?? 'Kids Pajamas';
              case 'School Uniforms':
                return l10n.subSubcategorySchoolUniforms ?? 'School Uniforms';
            }
            break;
          case 'Kids Footwear':
            switch (subSubKey) {
              case 'Kids Sneakers':
                return l10n.subSubcategoryKidsSneakers ?? 'Kids Sneakers';
              case 'Kids Sandals':
                return l10n.subSubcategoryKidsSandals ?? 'Kids Sandals';
              case 'Kids Boots':
                return l10n.subSubcategoryKidsBoots ?? 'Kids Boots';
              case 'School Shoes':
                return l10n.subSubcategorySchoolShoes ?? 'School Shoes';
              case 'Sports Shoes':
                return l10n.subSubcategorySportsShoes ?? 'Sports Shoes';
              case 'Rain Boots':
                return l10n.subSubcategoryKidsRainBoots ?? 'Rain Boots';
              case 'Kids Slippers':
                return l10n.subSubcategoryKidsSlippers ?? 'Kids Slippers';
            }
            break;
          case 'Toys & Games':
            switch (subSubKey) {
              case 'Educational Toys':
                return l10n.subSubcategoryEducationalToys ?? 'Educational Toys';
              case 'Plush Toys':
                return l10n.subSubcategoryPlushToys ?? 'Plush Toys';
              case 'Building Blocks':
                return l10n.subSubcategoryBuildingBlocks ?? 'Building Blocks';
              case 'Dolls & Action Figures':
                return l10n.subSubcategoryDollsActionFigures ??
                    'Dolls & Action Figures';
              case 'Puzzles':
                return l10n.subSubcategoryPuzzles ?? 'Puzzles';
              case 'Board Games':
                return l10n.subSubcategoryBoardGames ?? 'Board Games';
              case 'Electronic Toys':
                return l10n.subSubcategoryElectronicToys ?? 'Electronic Toys';
              case 'Outdoor Play':
                return l10n.subSubcategoryOutdoorPlay ?? 'Outdoor Play';
            }
            break;
          case 'Baby Care':
            switch (subSubKey) {
              case 'Diapers':
                return l10n.subSubcategoryDiapers ?? 'Diapers';
              case 'Baby Wipes':
                return l10n.subSubcategoryBabyWipes ?? 'Baby Wipes';
              case 'Baby Skincare':
                return l10n.subSubcategoryBabySkincare ?? 'Baby Skincare';
              case 'Baby Bath Products':
                return l10n.subSubcategoryBabyBathProducts ??
                    'Baby Bath Products';
              case 'Baby Health':
                return l10n.subSubcategoryBabyHealth ?? 'Baby Health';
              case 'Baby Monitors':
                return l10n.subSubcategoryBabyMonitors ?? 'Baby Monitors';
            }
            break;
          case 'Maternity':
            switch (subSubKey) {
              case 'Maternity Clothing':
                return l10n.subSubcategoryMaternityClothing ??
                    'Maternity Clothing';
              case 'Nursing Bras':
                return l10n.subSubcategoryNursingBras ?? 'Nursing Bras';
              case 'Maternity Accessories':
                return l10n.subSubcategoryMaternityAccessories ??
                    'Maternity Accessories';
              case 'Pregnancy Support':
                return l10n.subSubcategoryPregnancySupport ??
                    'Pregnancy Support';
            }
            break;
          case 'Strollers & Car Seats':
            switch (subSubKey) {
              case 'Strollers':
                return l10n.subSubcategoryStrollers ?? 'Strollers';
              case 'Car Seats':
                return l10n.subSubcategoryCarSeats ?? 'Car Seats';
              case 'Travel Systems':
                return l10n.subSubcategoryTravelSystems ?? 'Travel Systems';
              case 'Booster Seats':
                return l10n.subSubcategoryBoosterSeats ?? 'Booster Seats';
              case 'Stroller Accessories':
                return l10n.subSubcategoryStrollerAccessories ??
                    'Stroller Accessories';
            }
            break;
          case 'Feeding & Nursing':
            switch (subSubKey) {
              case 'Baby Bottles':
                return l10n.subSubcategoryBabyBottles ?? 'Baby Bottles';
              case 'Breast Pumps':
                return l10n.subSubcategoryBreastPumps ?? 'Breast Pumps';
              case 'Pacifiers':
                return l10n.subSubcategoryPacifiers ?? 'Pacifiers';
              case 'High Chairs':
                return l10n.subSubcategoryHighChairs ?? 'High Chairs';
              case 'Feeding Accessories':
                return l10n.subSubcategoryFeedingAccessories ??
                    'Feeding Accessories';
              case 'Baby Food':
                return l10n.subSubcategoryBabyFood ?? 'Baby Food';
            }
            break;
          case 'Safety & Security':
            switch (subSubKey) {
              case 'Baby Gates':
                return l10n.subSubcategoryBabyGates ?? 'Baby Gates';
              case 'Outlet Covers':
                return l10n.subSubcategoryOutletCovers ?? 'Outlet Covers';
              case 'Cabinet Locks':
                return l10n.subSubcategoryCabinetLocks ?? 'Cabinet Locks';
              case 'Corner Guards':
                return l10n.subSubcategoryCornerGuards ?? 'Corner Guards';
              case 'Baby Monitors':
                return l10n.subSubcategorySafetyBabyMonitors ?? 'Baby Monitors';
            }
            break;
          case 'Educational':
            switch (subSubKey) {
              case 'Learning Toys':
                return l10n.subSubcategoryLearningToys ?? 'Learning Toys';
              case 'Educational Books':
                return l10n.subSubcategoryEducationalBooks ??
                    'Educational Books';
              case 'Flash Cards':
                return l10n.subSubcategoryFlashCards ?? 'Flash Cards';
              case 'Science Kits':
                return l10n.subSubcategoryScienceKits ?? 'Science Kits';
              case 'Musical Instruments':
                return l10n.subSubcategoryEducationalMusicalInstruments ??
                    'Musical Instruments';
            }
            break;
        }
        break;
      case 'Home & Furniture':
        switch (parentSubcategoryKey) {
          case 'Living Room Furniture':
            switch (subSubKey) {
              case 'Sofas':
                return l10n.subSubcategorySofas ?? 'Sofas';
              case 'Armchairs':
                return l10n.subSubcategoryArmchairs ?? 'Armchairs';
              case 'Coffee Tables':
                return l10n.subSubcategoryCoffeeTables ?? 'Coffee Tables';
              case 'TV Stands':
                return l10n.subSubcategoryTVStands ?? 'TV Stands';
              case 'Bookcases':
                return l10n.subSubcategoryBookcases ?? 'Bookcases';
              case 'Side Tables':
                return l10n.subSubcategorySideTables ?? 'Side Tables';
              case 'Ottoman':
                return l10n.subSubcategoryOttoman ?? 'Ottoman';
              case 'Recliners':
                return l10n.subSubcategoryRecliners ?? 'Recliners';
            }
            break;
          case 'Bedroom Furniture':
            switch (subSubKey) {
              case 'Beds':
                return l10n.subSubcategoryBeds ?? 'Beds';
              case 'Mattresses':
                return l10n.subSubcategoryMattresses ?? 'Mattresses';
              case 'Wardrobes':
                return l10n.subSubcategoryWardrobes ?? 'Wardrobes';
              case 'Dressers':
                return l10n.subSubcategoryDressers ?? 'Dressers';
              case 'Nightstands':
                return l10n.subSubcategoryNightstands ?? 'Nightstands';
              case 'Mirrors':
                return l10n.subSubcategoryMirrors ?? 'Mirrors';
              case 'Bed Frames':
                return l10n.subSubcategoryBedFrames ?? 'Bed Frames';
              case 'Headboards':
                return l10n.subSubcategoryHeadboards ?? 'Headboards';
            }
            break;
          case 'Kitchen & Dining':
            switch (subSubKey) {
              case 'Dining Tables':
                return l10n.subSubcategoryDiningTables ?? 'Dining Tables';
              case 'Dining Chairs':
                return l10n.subSubcategoryDiningChairs ?? 'Dining Chairs';
              case 'Bar Stools':
                return l10n.subSubcategoryBarStools ?? 'Bar Stools';
              case 'Kitchen Islands':
                return l10n.subSubcategoryKitchenIslands ?? 'Kitchen Islands';
              case 'Cookware':
                return l10n.subSubcategoryCookware ?? 'Cookware';
              case 'Dinnerware':
                return l10n.subSubcategoryDinnerware ?? 'Dinnerware';
              case 'Glassware':
                return l10n.subSubcategoryGlassware ?? 'Glassware';
              case 'Kitchen Appliances':
                return l10n.subSubcategoryKitchenAppliances ??
                    'Kitchen Appliances';
              case 'Utensils':
                return l10n.subSubcategoryUtensils ?? 'Utensils';
            }
            break;
          case 'Bathroom':
            switch (subSubKey) {
              case 'Bathroom Vanities':
                return l10n.subSubcategoryBathroomVanities ??
                    'Bathroom Vanities';
              case 'Shower Curtains':
                return l10n.subSubcategoryShowerCurtains ?? 'Shower Curtains';
              case 'Bath Mats':
                return l10n.subSubcategoryBathMats ?? 'Bath Mats';
              case 'Towel Racks':
                return l10n.subSubcategoryTowelRacks ?? 'Towel Racks';
              case 'Bathroom Storage':
                return l10n.subSubcategoryBathroomStorage ?? 'Bathroom Storage';
              case 'Mirrors':
                return l10n.subSubcategoryBathroomMirrors ?? 'Mirrors';
              case 'Accessories':
                return l10n.subSubcategoryBathroomAccessories ?? 'Accessories';
            }
            break;
          case 'Home Decor':
            switch (subSubKey) {
              case 'Wall Art':
                return l10n.subSubcategoryWallArt ?? 'Wall Art';
              case 'Decorative Objects':
                return l10n.subSubcategoryDecorativeObjects ??
                    'Decorative Objects';
              case 'Candles':
                return l10n.subSubcategoryCandles ?? 'Candles';
              case 'Vases':
                return l10n.subSubcategoryVases ?? 'Vases';
              case 'Picture Frames':
                return l10n.subSubcategoryPictureFrames ?? 'Picture Frames';
              case 'Clocks':
                return l10n.subSubcategoryClocks ?? 'Clocks';
              case 'Artificial Plants':
                return l10n.subSubcategoryArtificialPlants ??
                    'Artificial Plants';
              case 'Sculptures':
                return l10n.subSubcategorySculptures ?? 'Sculptures';
            }
            break;
          case 'Lighting':
            switch (subSubKey) {
              case 'Ceiling Lights':
                return l10n.subSubcategoryCeilingLights ?? 'Ceiling Lights';
              case 'Table Lamps':
                return l10n.subSubcategoryTableLamps ?? 'Table Lamps';
              case 'Floor Lamps':
                return l10n.subSubcategoryFloorLamps ?? 'Floor Lamps';
              case 'Wall Lights':
                return l10n.subSubcategoryWallLights ?? 'Wall Lights';
              case 'Pendant Lights':
                return l10n.subSubcategoryPendantLights ?? 'Pendant Lights';
              case 'Chandelier':
                return l10n.subSubcategoryChandelier ?? 'Chandelier';
              case 'String Lights':
                return l10n.subSubcategoryStringLights ?? 'String Lights';
              case 'Night Lights':
                return l10n.subSubcategoryNightLights ?? 'Night Lights';
            }
            break;
          case 'Storage & Organization':
            switch (subSubKey) {
              case 'Shelving Units':
                return l10n.subSubcategoryShelvingUnits ?? 'Shelving Units';
              case 'Storage Boxes':
                return l10n.subSubcategoryStorageBoxes ?? 'Storage Boxes';
              case 'Baskets':
                return l10n.subSubcategoryBaskets ?? 'Baskets';
              case 'Hangers':
                return l10n.subSubcategoryHangers ?? 'Hangers';
              case 'Closet Organizers':
                return l10n.subSubcategoryClosetOrganizers ??
                    'Closet Organizers';
              case 'Drawer Organizers':
                return l10n.subSubcategoryDrawerOrganizers ??
                    'Drawer Organizers';
              case 'Storage Bins':
                return l10n.subSubcategoryStorageBins ?? 'Storage Bins';
            }
            break;
          case 'Textiles & Soft Furnishing':
            switch (subSubKey) {
              case 'Curtains':
                return l10n.subSubcategoryCurtains ?? 'Curtains';
              case 'Blinds':
                return l10n.subSubcategoryBlinds ?? 'Blinds';
              case 'Rugs':
                return l10n.subSubcategoryRugs ?? 'Rugs';
              case 'Cushions':
                return l10n.subSubcategoryCushions ?? 'Cushions';
              case 'Throws':
                return l10n.subSubcategoryThrows ?? 'Throws';
              case 'Bed Linens':
                return l10n.subSubcategoryBedLinens ?? 'Bed Linens';
              case 'Towels':
                return l10n.subSubcategoryTowels ?? 'Towels';
              case 'Blankets':
                return l10n.subSubcategoryBlankets ?? 'Blankets';
            }
            break;
          case 'Garden & Outdoor':
            switch (subSubKey) {
              case 'Garden Furniture':
                return l10n.subSubcategoryGardenFurniture ?? 'Garden Furniture';
              case 'Plant Pots':
                return l10n.subSubcategoryPlantPots ?? 'Plant Pots';
              case 'Garden Tools':
                return l10n.subSubcategoryGardenTools ?? 'Garden Tools';
              case 'Outdoor Lighting':
                return l10n.subSubcategoryOutdoorLighting ?? 'Outdoor Lighting';
              case 'BBQ & Grills':
                return l10n.subSubcategoryBBQGrills ?? 'BBQ & Grills';
              case 'Umbrellas':
                return l10n.subSubcategoryUmbrellas ?? 'Umbrellas';
              case 'Garden Decor':
                return l10n.subSubcategoryGardenDecor ?? 'Garden Decor';
            }
            break;
        }
        break;
      case 'Beauty & Personal Care':
        switch (parentSubcategoryKey) {
          case 'Skincare':
            switch (subSubKey) {
              case 'Cleansers':
                return l10n.subSubcategoryCleaners ?? 'Cleansers';
              case 'Moisturizers':
                return l10n.subSubcategoryMoisturizers ?? 'Moisturizers';
              case 'Serums':
                return l10n.subSubcategorySerums ?? 'Serums';
              case 'Face Masks':
                return l10n.subSubcategoryFaceMasks ?? 'Face Masks';
              case 'Sunscreen':
                return l10n.subSubcategorySunscreen ?? 'Sunscreen';
              case 'Toners':
                return l10n.subSubcategoryToners ?? 'Toners';
              case 'Eye Creams':
                return l10n.subSubcategoryEyeCreams ?? 'Eye Creams';
              case 'Anti-Aging':
                return l10n.subSubcategoryAntiAging ?? 'Anti-Aging';
              case 'Acne Treatment':
                return l10n.subSubcategoryAcneTreatment ?? 'Acne Treatment';
            }
            break;
          case 'Makeup':
            switch (subSubKey) {
              case 'Foundation':
                return l10n.subSubcategoryFoundation ?? 'Foundation';
              case 'Concealer':
                return l10n.subSubcategoryConcealer ?? 'Concealer';
              case 'Powder':
                return l10n.subSubcategoryPowder ?? 'Powder';
              case 'Blush':
                return l10n.subSubcategoryBlush ?? 'Blush';
              case 'Bronzer':
                return l10n.subSubcategoryBronzer ?? 'Bronzer';
              case 'Highlighter':
                return l10n.subSubcategoryHighlighter ?? 'Highlighter';
              case 'Eyeshadow':
                return l10n.subSubcategoryEyeshadow ?? 'Eyeshadow';
              case 'Eyeliner':
                return l10n.subSubcategoryEyeliner ?? 'Eyeliner';
              case 'Mascara':
                return l10n.subSubcategoryMascara ?? 'Mascara';
              case 'Lipstick':
                return l10n.subSubcategoryLipstick ?? 'Lipstick';
              case 'Lip Gloss':
                return l10n.subSubcategoryLipGloss ?? 'Lip Gloss';
              case 'Makeup Brushes':
                return l10n.subSubcategoryMakeupBrushes ?? 'Makeup Brushes';
            }
            break;
          case 'Haircare':
            switch (subSubKey) {
              case 'Shampoo':
                return l10n.subSubcategoryShampoo ?? 'Shampoo';
              case 'Conditioner':
                return l10n.subSubcategoryConditioner ?? 'Conditioner';
              case 'Hair Masks':
                return l10n.subSubcategoryHairMasks ?? 'Hair Masks';
              case 'Hair Oils':
                return l10n.subSubcategoryHairOils ?? 'Hair Oils';
              case 'Styling Products':
                return l10n.subSubcategoryStylingProducts ?? 'Styling Products';
              case 'Hair Color':
                return l10n.subSubcategoryHairColor ?? 'Hair Color';
              case 'Hair Tools':
                return l10n.subSubcategoryHairTools ?? 'Hair Tools';
            }
            break;
          case 'Fragrances':
            switch (subSubKey) {
              case 'Perfumes':
                return l10n.subSubcategoryPerfumes ?? 'Perfumes';
              case 'Eau de Toilette':
                return l10n.subSubcategoryEauDeToilette ?? 'Eau de Toilette';
              case 'Body Sprays':
                return l10n.subSubcategoryBodySprays ?? 'Body Sprays';
              case 'Deodorants':
                return l10n.subSubcategoryDeodorants ?? 'Deodorants';
              case 'Cologne':
                return l10n.subSubcategoryColognes ?? 'Cologne';
              case 'Essential Oils':
                return l10n.subSubcategoryEssentialOils ?? 'Essential Oils';
            }
            break;
          case 'Personal Hygiene':
            switch (subSubKey) {
              case 'Body Wash':
                return l10n.subSubcategoryBodyWash ?? 'Body Wash';
              case 'Soap':
                return l10n.subSubcategorySoap ?? 'Soap';
              case 'Shampoo':
                return l10n.subSubcategoryPersonalHygieneShampoo ?? 'Shampoo';
              case 'Deodorants':
                return l10n.subSubcategoryPersonalHygieneDeodorants ??
                    'Deodorants';
              case 'Feminine Care':
                return l10n.subSubcategoryFeminineCare ?? 'Feminine Care';
              case 'Men\'s Grooming':
                return l10n.subSubcategoryMensGrooming ?? 'Men\'s Grooming';
              case 'Intimate Care':
                return l10n.subSubcategoryIntimateCare ?? 'Intimate Care';
            }
            break;
          case 'Nail Care':
            switch (subSubKey) {
              case 'Nail Polish':
                return l10n.subSubcategoryNailPolish ?? 'Nail Polish';
              case 'Nail Tools':
                return l10n.subSubcategoryNailTools ?? 'Nail Tools';
              case 'Nail Treatments':
                return l10n.subSubcategoryNailTreatments ?? 'Nail Treatments';
              case 'Nail Art':
                return l10n.subSubcategoryNailArt ?? 'Nail Art';
              case 'Cuticle Care':
                return l10n.subSubcategoryCuticleCare ?? 'Cuticle Care';
              case 'Nail Files':
                return l10n.subSubcategoryNailFiles ?? 'Nail Files';
            }
            break;
          case 'Body Care':
            switch (subSubKey) {
              case 'Body Lotions':
                return l10n.subSubcategoryBodyLotions ?? 'Body Lotions';
              case 'Body Oils':
                return l10n.subSubcategoryBodyOils ?? 'Body Oils';
              case 'Body Scrubs':
                return l10n.subSubcategoryBodyScrubs ?? 'Body Scrubs';
              case 'Hand Cream':
                return l10n.subSubcategoryHandCream ?? 'Hand Cream';
              case 'Foot Care':
                return l10n.subSubcategoryFootCare ?? 'Foot Care';
              case 'Bath Products':
                return l10n.subSubcategoryBathProducts ?? 'Bath Products';
              case 'Massage Oils':
                return l10n.subSubcategoryMassageOils ?? 'Massage Oils';
            }
            break;
          case 'Oral Care':
            switch (subSubKey) {
              case 'Toothbrushes':
                return l10n.subSubcategoryToothbrushes ?? 'Toothbrushes';
              case 'Toothpaste':
                return l10n.subSubcategoryToothpaste ?? 'Toothpaste';
              case 'Mouthwash':
                return l10n.subSubcategoryMouthwash ?? 'Mouthwash';
              case 'Dental Floss':
                return l10n.subSubcategoryDentalFloss ?? 'Dental Floss';
              case 'Teeth Whitening':
                return l10n.subSubcategoryTeethWhitening ?? 'Teeth Whitening';
              case 'Oral Health':
                return l10n.subSubcategoryOralHealth ?? 'Oral Health';
            }
            break;
          case 'Beauty Tools & Accessories':
            switch (subSubKey) {
              case 'Makeup Brushes':
                return l10n.subSubcategoryBeautyMakeupBrushes ??
                    'Makeup Brushes';
              case 'Beauty Sponges':
                return l10n.subSubcategoryBeautySponges ?? 'Beauty Sponges';
              case 'Hair Brushes':
                return l10n.subSubcategoryHairBrushes ?? 'Hair Brushes';
              case 'Mirrors':
                return l10n.subSubcategoryBeautyMirrors ?? 'Mirrors';
              case 'Tweezers':
                return l10n.subSubcategoryTweezers ?? 'Tweezers';
              case 'Nail Clippers':
                return l10n.subSubcategoryNailClippers ?? 'Nail Clippers';
              case 'Beauty Cases':
                return l10n.subSubcategoryBeautyCases ?? 'Beauty Cases';
            }
            break;
        }
        break;
      case 'Bags & Luggage':
        switch (parentSubcategoryKey) {
          case 'Handbags':
            switch (subSubKey) {
              case 'Tote Bags':
                return l10n.subSubcategoryToteBags ?? 'Tote Bags';
              case 'Shoulder Bags':
                return l10n.subSubcategoryShoulderBags ?? 'Shoulder Bags';
              case 'Crossbody Bags':
                return l10n.subSubcategoryCrossbodyBags ?? 'Crossbody Bags';
              case 'Clutches':
                return l10n.subSubcategoryClutches ?? 'Clutches';
              case 'Evening Bags':
                return l10n.subSubcategoryEveningBags ?? 'Evening Bags';
              case 'Satchels':
                return l10n.subSubcategorySatchels ?? 'Satchels';
              case 'Hobo Bags':
                return l10n.subSubcategoryHoboBags ?? 'Hobo Bags';
            }
            break;
          case 'Backpacks':
            switch (subSubKey) {
              case 'School Backpacks':
                return l10n.subSubcategorySchoolBackpacks ?? 'School Backpacks';
              case 'Travel Backpacks':
                return l10n.subSubcategoryTravelBackpacks ?? 'Travel Backpacks';
              case 'Laptop Backpacks':
                return l10n.subSubcategoryLaptopBackpacks ?? 'Laptop Backpacks';
              case 'Hiking Backpacks':
                return l10n.subSubcategoryHikingBackpacks ?? 'Hiking Backpacks';
              case 'Casual Backpacks':
                return l10n.subSubcategoryCasualBackpacks ?? 'Casual Backpacks';
              case 'Kids Backpacks':
                return l10n.subSubcategoryKidsBackpacks ?? 'Kids Backpacks';
            }
            break;
          case 'Travel Luggage':
            switch (subSubKey) {
              case 'Suitcases':
                return l10n.subSubcategorySuitcases ?? 'Suitcases';
              case 'Carry-On Bags':
                return l10n.subSubcategoryCarryOnBags ?? 'Carry-On Bags';
              case 'Travel Duffel Bags':
                return l10n.subSubcategoryTravelDuffelBags ??
                    'Travel Duffel Bags';
              case 'Luggage Sets':
                return l10n.subSubcategoryLuggageSets ?? 'Luggage Sets';
              case 'Garment Bags':
                return l10n.subSubcategoryGarmentBags ?? 'Garment Bags';
              case 'Travel Accessories':
                return l10n.subSubcategoryTravelAccessories ??
                    'Travel Accessories';
            }
            break;
          case 'Briefcases & Business Bags':
            switch (subSubKey) {
              case 'Briefcases':
                return l10n.subSubcategoryBriefcases ?? 'Briefcases';
              case 'Laptop Bags':
                return l10n.subSubcategoryLaptopBags ?? 'Laptop Bags';
              case 'Messenger Bags':
                return l10n.subSubcategoryMessengerBags ?? 'Messenger Bags';
              case 'Portfolio Bags':
                return l10n.subSubcategoryPortfolioBags ?? 'Portfolio Bags';
              case 'Business Totes':
                return l10n.subSubcategoryBusinessTotes ?? 'Business Totes';
            }
            break;
          case 'Sports & Gym Bags':
            switch (subSubKey) {
              case 'Gym Bags':
                return l10n.subSubcategoryGymBags ?? 'Gym Bags';
              case 'Sports Duffel Bags':
                return l10n.subSubcategorySportsDuffelBags ??
                    'Sports Duffel Bags';
              case 'Equipment Bags':
                return l10n.subSubcategoryEquipmentBags ?? 'Equipment Bags';
              case 'Yoga Bags':
                return l10n.subSubcategoryYogaBags ?? 'Yoga Bags';
              case 'Swimming Bags':
                return l10n.subSubcategorySwimmingBags ?? 'Swimming Bags';
            }
            break;
          case 'Wallets & Small Accessories':
            switch (subSubKey) {
              case 'Wallets':
                return l10n.subSubcategoryWalletsSmall ?? 'Wallets';
              case 'Card Holders':
                return l10n.subSubcategoryCardHolders ?? 'Card Holders';
              case 'Coin Purses':
                return l10n.subSubcategoryCoinPurses ?? 'Coin Purses';
              case 'Key Cases':
                return l10n.subSubcategoryKeyCases ?? 'Key Cases';
              case 'Phone Cases':
                return l10n.subSubcategoryPhoneCasesSmall ?? 'Phone Cases';
              case 'Passport Holders':
                return l10n.subSubcategoryPassportHolders ?? 'Passport Holders';
            }
            break;
          case 'Specialty Bags':
            switch (subSubKey) {
              case 'Camera Bags':
                return l10n.subSubcategoryCameraBags ?? 'Camera Bags';
              case 'Diaper Bags':
                return l10n.subSubcategoryDiaperBags ?? 'Diaper Bags';
              case 'Lunch Bags':
                return l10n.subSubcategoryLunchBags ?? 'Lunch Bags';
              case 'Tool Bags':
                return l10n.subSubcategoryToolBags ?? 'Tool Bags';
              case 'Cosmetic Bags':
                return l10n.subSubcategoryCosmeticBags ?? 'Cosmetic Bags';
              case 'Beach Bags':
                return l10n.subSubcategoryBeachBags ?? 'Beach Bags';
            }
            break;
        }
        break;
      case 'Electronics':
        switch (parentSubcategoryKey) {
          case 'Smartphones & Accessories':
            switch (subSubKey) {
              case 'Smartphones':
                return l10n.subSubcategorySmartphones ?? 'Smartphones';
              case 'Phone Cases':
                return l10n.subSubcategoryPhoneCasesElectronics ??
                    'Phone Cases';
              case 'Screen Protectors':
                return l10n.subSubcategoryScreenProtectors ??
                    'Screen Protectors';
              case 'Chargers':
                return l10n.subSubcategoryChargers ?? 'Chargers';
              case 'Power Banks':
                return l10n.subSubcategoryPowerBanks ?? 'Power Banks';
              case 'Phone Stands':
                return l10n.subSubcategoryPhoneStands ?? 'Phone Stands';
              case 'Wireless Chargers':
                return l10n.subSubcategoryWirelessChargers ??
                    'Wireless Chargers';
            }
            break;
          case 'Computers & Laptops':
            switch (subSubKey) {
              case 'Laptops':
                return l10n.subSubcategoryLaptops ?? 'Laptops';
              case 'Desktop Computers':
                return l10n.subSubcategoryDesktopComputers ??
                    'Desktop Computers';
              case 'Tablets':
                return l10n.subSubcategoryTablets ?? 'Tablets';
              case 'Monitors':
                return l10n.subSubcategoryMonitors ?? 'Monitors';
              case 'Keyboards':
                return l10n.subSubcategoryKeyboards ?? 'Keyboards';
              case 'Mice':
                return l10n.subSubcategoryMice ?? 'Mice';
              case 'Laptop Accessories':
                return l10n.subSubcategoryLaptopAccessories ??
                    'Laptop Accessories';
              case 'Computer Components':
                return l10n.subSubcategoryComputerComponents ??
                    'Computer Components';
            }
            break;
          case 'TVs & Home Entertainment':
            switch (subSubKey) {
              case 'Smart TVs':
                return l10n.subSubcategorySmartTVs ?? 'Smart TVs';
              case 'Projectors':
                return l10n.subSubcategoryProjectors ?? 'Projectors';
              case 'Streaming Devices':
                return l10n.subSubcategoryStreamingDevices ??
                    'Streaming Devices';
              case 'TV Mounts & Stands':
                return l10n.subSubcategoryTVMountsStands ??
                    'TV Mounts & Stands';
              case 'Home Theater Systems':
                return l10n.subSubcategoryHomeTheaterSystems ??
                    'Home Theater Systems';
              case 'TV Cables & Accessories':
                return l10n.subSubcategoryTVCablesAccessories ??
                    'TV Cables & Accessories';
              case 'Remote Controls':
                return l10n.subSubcategoryRemoteControls ?? 'Remote Controls';
              case 'TV Antennas':
                return l10n.subSubcategoryTVAntennas ?? 'TV Antennas';
              case 'Media Players':
                return l10n.subSubcategoryMediaPlayers ?? 'Media Players';
            }
            break;
          case 'Audio Equipment':
            switch (subSubKey) {
              case 'Headphones':
                return l10n.subSubcategoryHeadphones ?? 'Headphones';
              case 'Earbuds':
                return l10n.subSubcategoryEarbuds ?? 'Earbuds';
              case 'Speakers':
                return l10n.subSubcategorySpeakers ?? 'Speakers';
              case 'Sound Systems':
                return l10n.subSubcategorySoundSystems ?? 'Sound Systems';
              case 'Soundbars':
                return l10n.subSubcategorySoundbars ?? 'Soundbars';
              case 'Microphones':
                return l10n.subSubcategoryMicrophones ?? 'Microphones';
              case 'Amplifiers':
                return l10n.subSubcategoryAmplifiers ?? 'Amplifiers';
              case 'Turntables':
                return l10n.subSubcategoryTurntables ?? 'Turntables';
              case 'Audio Cables':
                return l10n.subSubcategoryAudioCables ?? 'Audio Cables';
            }
            break;
          case 'Gaming':
            switch (subSubKey) {
              case 'Gaming Consoles':
                return l10n.subSubcategoryGamingConsoles ?? 'Gaming Consoles';
              case 'Video Games':
                return l10n.subSubcategoryVideoGames ?? 'Video Games';
              case 'Gaming Controllers':
                return l10n.subSubcategoryGamingControllers ??
                    'Gaming Controllers';
              case 'Gaming Headsets':
                return l10n.subSubcategoryGamingHeadsets ?? 'Gaming Headsets';
              case 'Gaming Chairs':
                return l10n.subSubcategoryGamingChairs ?? 'Gaming Chairs';
              case 'VR Headsets':
                return l10n.subSubcategoryVRHeadsets ?? 'VR Headsets';
              case 'Gaming Accessories':
                return l10n.subSubcategoryGamingAccessories ??
                    'Gaming Accessories';
            }
            break;
          case 'Smart Home & IoT':
            switch (subSubKey) {
              case 'Smart Speakers':
                return l10n.subSubcategorySmartSpeakers ?? 'Smart Speakers';
              case 'Smart Lights':
                return l10n.subSubcategorySmartLights ?? 'Smart Lights';
              case 'Smart Plugs':
                return l10n.subSubcategorySmartPlugs ?? 'Smart Plugs';
              case 'Security Cameras':
                return l10n.subSubcategorySecurityCameras ?? 'Security Cameras';
              case 'Smart Thermostats':
                return l10n.subSubcategorySmartThermostats ??
                    'Smart Thermostats';
              case 'Smart Locks':
                return l10n.subSubcategorySmartLocks ?? 'Smart Locks';
              case 'Home Automation':
                return l10n.subSubcategoryHomeAutomation ?? 'Home Automation';
            }
            break;
          case 'Cameras & Photography':
            switch (subSubKey) {
              case 'Digital Cameras':
                return l10n.subSubcategoryDigitalCameras ?? 'Digital Cameras';
              case 'DSLR Cameras':
                return l10n.subSubcategoryDSLRCameras ?? 'DSLR Cameras';
              case 'Action Cameras':
                return l10n.subSubcategoryActionCameras ?? 'Action Cameras';
              case 'Camera Lenses':
                return l10n.subSubcategoryCameraLenses ?? 'Camera Lenses';
              case 'Tripods':
                return l10n.subSubcategoryTripods ?? 'Tripods';
              case 'Camera Accessories':
                return l10n.subSubcategoryCameraAccessories ??
                    'Camera Accessories';
              case 'Photography Equipment':
                return l10n.subSubcategoryPhotographyEquipment ??
                    'Photography Equipment';
            }
            break;
          case 'Wearable Tech':
            switch (subSubKey) {
              case 'Smartwatches':
                return l10n.subSubcategorySmartwatchesWearable ??
                    'Smartwatches';
              case 'Fitness Trackers':
                return l10n.subSubcategoryFitnessTrackers ?? 'Fitness Trackers';
              case 'Smart Glasses':
                return l10n.subSubcategorySmartGlasses ?? 'Smart Glasses';
              case 'Health Monitors':
                return l10n.subSubcategoryHealthMonitors ?? 'Health Monitors';
              case 'Wearable Accessories':
                return l10n.subSubcategoryWearableAccessories ??
                    'Wearable Accessories';
            }
            break;
          case 'Home Appliances':
            switch (subSubKey) {
              case 'Kitchen Appliances':
                return l10n.subSubcategoryKitchenAppliancesElectronics ??
                    'Kitchen Appliances';
              case 'White Goods':
                return l10n.subSubcategoryWhiteGoods ?? 'White Goods';
              case 'Air Conditioning':
                return l10n.subSubcategoryAirConditioning ?? 'Air Conditioning';
              case 'Heating':
                return l10n.subSubcategoryHeating ?? 'Heating';
            }
            break;
          case 'Personal Care Electronics':
            switch (subSubKey) {
              case 'Hair Dryers':
                return l10n.subSubcategoryHairDryers ?? 'Hair Dryers';
              case 'Hair Straighteners':
                return l10n.subSubcategoryHairStraighteners ??
                    'Hair Straighteners';
              case 'Electric Shavers':
                return l10n.subSubcategoryElectricShavers ?? 'Electric Shavers';
              case 'Toothbrushes':
                return l10n.subSubcategoryElectricToothbrushes ??
                    'Toothbrushes';
              case 'Beauty Devices':
                return l10n.subSubcategoryBeautyDevices ?? 'Beauty Devices';
              case 'Health Monitors':
                return l10n.subSubcategoryPersonalHealthMonitors ??
                    'Health Monitors';
            }
            break;
        }
        break;
      case 'Flowers & Gifts':
        switch (parentSubcategoryKey) {
          case 'Bouquets & Arrangements':
            switch (subSubKey) {
              case 'Bouquets':
                return l10n.subSubcategoryBouquets ?? 'Bouquets';
              case 'Flower Arrangements':
                return l10n.subSubcategoryFlowerArrangements ??
                    'Flower Arrangements';
              case 'Mixed Arrangements':
                return l10n.subSubcategoryMixedArrangements ??
                    'Mixed Arrangements';
              case 'Single Flower Types':
                return l10n.subSubcategorySingleFlowerTypes ??
                    'Single Flower Types';
              case 'Seasonal Arrangements':
                return l10n.subSubcategorySeasonalArrangements ??
                    'Seasonal Arrangements';
            }
            break;
          case 'Potted Plants':
            switch (subSubKey) {
              case 'Indoor Plants':
                return l10n.subSubcategoryIndoorPlants ?? 'Indoor Plants';
              case 'Outdoor Plants':
                return l10n.subSubcategoryOutdoorPlants ?? 'Outdoor Plants';
              case 'Succulents':
                return l10n.subSubcategorySucculents ?? 'Succulents';
              case 'Orchids':
                return l10n.subSubcategoryOrchids ?? 'Orchids';
              case 'Bonsai':
                return l10n.subSubcategoryBonsai ?? 'Bonsai';
              case 'Cacti':
                return l10n.subSubcategoryCacti ?? 'Cacti';
            }
            break;
          case 'Gift Arrangements':
            switch (subSubKey) {
              case 'Chocolate Arrangements':
                return l10n.subSubcategoryChocolateArrangements ??
                    'Chocolate Arrangements';
              case 'Edible Arrangements':
                return l10n.subSubcategoryEdibleArrangements ??
                    'Edible Arrangements';
              case 'Fruit Baskets':
                return l10n.subSubcategoryFruitBaskets ?? 'Fruit Baskets';
              case 'Gift Combos':
                return l10n.subSubcategoryGiftCombos ?? 'Gift Combos';
              case 'Balloon Arrangements':
                return l10n.subSubcategoryBalloonArrangements ??
                    'Balloon Arrangements';
            }
            break;
          case 'Flower Accessories':
            switch (subSubKey) {
              case 'Vases':
                return l10n.subSubcategoryVases ?? 'Vases';
              case 'Planters & Pots':
                return l10n.subSubcategoryPlantersPots ?? 'Planters & Pots';
              case 'Floral Foam':
                return l10n.subSubcategoryFloralFoam ?? 'Floral Foam';
              case 'Ribbons & Wraps':
                return l10n.subSubcategoryRibbonsWraps ?? 'Ribbons & Wraps';
              case 'Plant Care Products':
                return l10n.subSubcategoryPlantCareProducts ??
                    'Plant Care Products';
              case 'Decorative Accessories':
                return l10n.subSubcategoryDecorativeAccessories ??
                    'Decorative Accessories';
            }
            break;
          case 'Wreaths & Centerpieces':
            switch (subSubKey) {
              case 'Funeral Wreaths':
                return l10n.subSubcategoryFuneralWreaths ?? 'Funeral Wreaths';
              case 'Decorative Wreaths':
                return l10n.subSubcategoryDecorativeWreaths ??
                    'Decorative Wreaths';
              case 'Table Centerpieces':
                return l10n.subSubcategoryTableCenterpieces ??
                    'Table Centerpieces';
              case 'Event Decorations':
                return l10n.subSubcategoryEventDecorations ??
                    'Event Decorations';
              case 'Seasonal Wreaths':
                return l10n.subSubcategorySeasonalWreaths ?? 'Seasonal Wreaths';
            }
            break;
        }
        break;
      case 'Sports & Outdoor':
        switch (parentSubcategoryKey) {
          case 'Fitness & Exercise':
            switch (subSubKey) {
              case 'Cardio Equipment':
                return l10n.subSubcategoryCardioEquipment ?? 'Cardio Equipment';
              case 'Strength Training':
                return l10n.subSubcategoryStrengthTraining ??
                    'Strength Training';
              case 'Yoga Equipment':
                return l10n.subSubcategoryYogaEquipment ?? 'Yoga Equipment';
              case 'Pilates Equipment':
                return l10n.subSubcategoryPilatesEquipment ??
                    'Pilates Equipment';
              case 'Home Gym':
                return l10n.subSubcategoryHomeGym ?? 'Home Gym';
              case 'Exercise Accessories':
                return l10n.subSubcategoryExerciseAccessories ??
                    'Exercise Accessories';
              case 'Recovery Equipment':
                return l10n.subSubcategoryRecoveryEquipment ??
                    'Recovery Equipment';
            }
            break;
          case 'Sports':
            switch (subSubKey) {
              case 'Football':
                return l10n.subSubcategoryFootball ?? 'Football';
              case 'Basketball':
                return l10n.subSubcategoryBasketball ?? 'Basketball';
              case 'Baseball':
                return l10n.subSubcategoryBaseball ?? 'Baseball';
              case 'Volleyball':
                return l10n.subSubcategoryVolleyball ?? 'Volleyball';
              case 'Tennis':
                return l10n.subSubcategoryTennis ?? 'Tennis';
              case 'Cricket':
                return l10n.subSubcategoryCricket ?? 'Cricket';
              case 'American Football':
                return l10n.subSubcategoryAmericanFootball ??
                    'American Football';
              case 'Golf':
                return l10n.subSubcategoryGolf ?? 'Golf';
              case 'Table Tennis':
                return l10n.subSubcategoryTableTennis ?? 'Table Tennis';
              case 'Badminton':
                return l10n.subSubcategoryBadminton ?? 'Badminton';
            }
            break;
          case 'Water Sports':
            switch (subSubKey) {
              case 'Swimming':
                return l10n.subSubcategorySwimming ?? 'Swimming';
              case 'Surfing':
                return l10n.subSubcategorySurfing ?? 'Surfing';
              case 'Kayaking':
                return l10n.subSubcategoryKayaking ?? 'Kayaking';
              case 'Diving':
                return l10n.subSubcategoryDiving ?? 'Diving';
              case 'Water Skiing':
                return l10n.subSubcategoryWaterSkiing ?? 'Water Skiing';
              case 'Fishing':
                return l10n.subSubcategoryFishing ?? 'Fishing';
              case 'Boating':
                return l10n.subSubcategoryBoating ?? 'Boating';
              case 'Water Safety':
                return l10n.subSubcategoryWaterSafety ?? 'Water Safety';
            }
            break;
          case 'Outdoor & Camping':
            switch (subSubKey) {
              case 'Camping Gear':
                return l10n.subSubcategoryCampingGear ?? 'Camping Gear';
              case 'Hiking Equipment':
                return l10n.subSubcategoryHikingEquipment ?? 'Hiking Equipment';
              case 'Backpacking':
                return l10n.subSubcategoryBackpacking ?? 'Backpacking';
              case 'Climbing Gear':
                return l10n.subSubcategoryClimbingGear ?? 'Climbing Gear';
              case 'Outdoor Clothing':
                return l10n.subSubcategoryOutdoorClothing ?? 'Outdoor Clothing';
              case 'Navigation':
                return l10n.subSubcategoryNavigation ?? 'Navigation';
              case 'Survival Gear':
                return l10n.subSubcategorySurvivalGear ?? 'Survival Gear';
            }
            break;
          case 'Winter Sports':
            switch (subSubKey) {
              case 'Skiing':
                return l10n.subSubcategorySkiing ?? 'Skiing';
              case 'Snowboarding':
                return l10n.subSubcategorySnowboarding ?? 'Snowboarding';
              case 'Ice Skating':
                return l10n.subSubcategoryIceSkating ?? 'Ice Skating';
              case 'Winter Clothing':
                return l10n.subSubcategoryWinterClothing ?? 'Winter Clothing';
              case 'Snow Equipment':
                return l10n.subSubcategorySnowEquipment ?? 'Snow Equipment';
              case 'Winter Accessories':
                return l10n.subSubcategoryWinterAccessories ??
                    'Winter Accessories';
            }
            break;
          case 'Cycling':
            switch (subSubKey) {
              case 'Bicycles':
                return l10n.subSubcategoryBicycles ?? 'Bicycles';
              case 'Bike Accessories':
                return l10n.subSubcategoryBikeAccessories ?? 'Bike Accessories';
              case 'Cycling Apparel':
                return l10n.subSubcategoryCyclingApparel ?? 'Cycling Apparel';
              case 'Bike Maintenance':
                return l10n.subSubcategoryBikeMaintenance ?? 'Bike Maintenance';
              case 'Bike Safety':
                return l10n.subSubcategoryBikeSafety ?? 'Bike Safety';
              case 'E-Bikes':
                return l10n.subSubcategoryEBikes ?? 'E-Bikes';
            }
            break;
          case 'Running & Athletics':
            switch (subSubKey) {
              case 'Running Shoes':
                return l10n.subSubcategoryRunningShoesAthletics ??
                    'Running Shoes';
              case 'Running Apparel':
                return l10n.subSubcategoryRunningApparel ?? 'Running Apparel';
              case 'Track & Field':
                return l10n.subSubcategoryTrackField ?? 'Track & Field';
              case 'Marathon Gear':
                return l10n.subSubcategoryMarathonGear ?? 'Marathon Gear';
              case 'Running Accessories':
                return l10n.subSubcategoryRunningAccessories ??
                    'Running Accessories';
              case 'Performance Monitoring':
                return l10n.subSubcategoryPerformanceMonitoring ??
                    'Performance Monitoring';
            }
            break;
          case 'Sports Accessories':
            switch (subSubKey) {
              case 'Sports Bags':
                return l10n.subSubcategorySportsBags ?? 'Sports Bags';
              case 'Protective Gear':
                return l10n.subSubcategoryProtectiveGear ?? 'Protective Gear';
              case 'Sports Nutrition':
                return l10n.subSubcategorySportsNutrition ?? 'Sports Nutrition';
              case 'Hydration':
                return l10n.subSubcategoryHydration ?? 'Hydration';
              case 'Sports Technology':
                return l10n.subSubcategorySportsTechnology ??
                    'Sports Technology';
              case 'Fan Gear':
                return l10n.subSubcategoryFanGear ?? 'Fan Gear';
            }
            break;
          case 'Sportswear':
            switch (subSubKey) {
              case 'Athletic Tops':
                return l10n.subSubcategoryAthleticTopsWear ?? 'Athletic Tops';
              case 'Athletic Bottoms':
                return l10n.subSubcategoryAthleticBottomsWear ??
                    'Athletic Bottoms';
              case 'Sports Bras':
                return l10n.subSubcategorySportsBrasWear ?? 'Sports Bras';
              case 'Athletic Shoes':
                return l10n.subSubcategoryAthleticShoes ?? 'Athletic Shoes';
              case 'Sports Accessories':
                return l10n.subSubcategorySportsAccessoriesWear ??
                    'Sports Accessories';
              case 'Team Jerseys':
                return l10n.subSubcategoryTeamJerseys ?? 'Team Jerseys';
            }
            break;
        }
        break;
      case 'Books, Stationery & Hobby':
        switch (parentSubcategoryKey) {
          case 'Books & Literature':
            switch (subSubKey) {
              case 'Fiction Books':
                return l10n.subSubcategoryFictionBooks ?? 'Fiction Books';
              case 'Non-Fiction Books':
                return l10n.subSubcategoryNonFictionBooks ??
                    'Non-Fiction Books';
              case 'Educational Books':
                return l10n.subSubcategoryEducationalBooksLiterature ??
                    'Educational Books';
              case 'Children\'s Books':
                return l10n.subSubcategoryChildrensBooks ?? 'Children\'s Books';
              case 'Reference Books':
                return l10n.subSubcategoryReferenceBooks ?? 'Reference Books';
              case 'Magazines':
                return l10n.subSubcategoryMagazines ?? 'Magazines';
              case 'Comics':
                return l10n.subSubcategoryComics ?? 'Comics';
              case 'E-Books':
                return l10n.subSubcategoryEBooks ?? 'E-Books';
            }
            break;
          case 'Office & School Supplies':
            switch (subSubKey) {
              case 'Notebooks':
                return l10n.subSubcategoryNotebooks ?? 'Notebooks';
              case 'Binders':
                return l10n.subSubcategoryBinders ?? 'Binders';
              case 'Folders':
                return l10n.subSubcategoryFolders ?? 'Folders';
              case 'Desk Accessories':
                return l10n.subSubcategoryDeskAccessories ?? 'Desk Accessories';
              case 'Calculators':
                return l10n.subSubcategoryCalculators ?? 'Calculators';
              case 'Labels':
                return l10n.subSubcategoryLabels ?? 'Labels';
              case 'Staplers':
                return l10n.subSubcategoryStaplers ?? 'Staplers';
              case 'Organizers':
                return l10n.subSubcategoryOrganizers ?? 'Organizers';
            }
            break;
          case 'Art & Craft Supplies':
            switch (subSubKey) {
              case 'Drawing Supplies':
                return l10n.subSubcategoryDrawingSupplies ?? 'Drawing Supplies';
              case 'Painting Supplies':
                return l10n.subSubcategoryPaintingSupplies ??
                    'Painting Supplies';
              case 'Craft Materials':
                return l10n.subSubcategoryCraftMaterials ?? 'Craft Materials';
              case 'Scrapbooking':
                return l10n.subSubcategoryScrapbooking ?? 'Scrapbooking';
              case 'Sewing Supplies':
                return l10n.subSubcategorySewingSupplies ?? 'Sewing Supplies';
              case 'Jewelry Making':
                return l10n.subSubcategoryJewelryMaking ?? 'Jewelry Making';
              case 'Model Building':
                return l10n.subSubcategoryModelBuilding ?? 'Model Building';
            }
            break;
          case 'Writing Instruments':
            switch (subSubKey) {
              case 'Pens':
                return l10n.subSubcategoryPens ?? 'Pens';
              case 'Pencils':
                return l10n.subSubcategoryPencils ?? 'Pencils';
              case 'Markers':
                return l10n.subSubcategoryMarkers ?? 'Markers';
              case 'Highlighters':
                return l10n.subSubcategoryHighlighters ?? 'Highlighters';
              case 'Fountain Pens':
                return l10n.subSubcategoryFountainPens ?? 'Fountain Pens';
              case 'Mechanical Pencils':
                return l10n.subSubcategoryMechanicalPencils ??
                    'Mechanical Pencils';
              case 'Erasers':
                return l10n.subSubcategoryErasers ?? 'Erasers';
            }
            break;
          case 'Paper Products':
            switch (subSubKey) {
              case 'Copy Paper':
                return l10n.subSubcategoryCopyPaper ?? 'Copy Paper';
              case 'Specialty Paper':
                return l10n.subSubcategorySpecialtyPaper ?? 'Specialty Paper';
              case 'Cardstock':
                return l10n.subSubcategoryCardstock ?? 'Cardstock';
              case 'Envelopes':
                return l10n.subSubcategoryEnvelopes ?? 'Envelopes';
              case 'Sticky Notes':
                return l10n.subSubcategoryStickyNotes ?? 'Sticky Notes';
              case 'Index Cards':
                return l10n.subSubcategoryIndexCards ?? 'Index Cards';
              case 'Construction Paper':
                return l10n.subSubcategoryConstructionPaper ??
                    'Construction Paper';
            }
            break;
          case 'Educational Materials':
            switch (subSubKey) {
              case 'Learning Games':
                return l10n.subSubcategoryLearningGames ?? 'Learning Games';
              case 'Flash Cards':
                return l10n.subSubcategoryFlashCardsEducational ??
                    'Flash Cards';
              case 'Educational Toys':
                return l10n.subSubcategoryEducationalToysStationery ??
                    'Educational Toys';
              case 'Science Kits':
                return l10n.subSubcategoryScienceKitsStationery ??
                    'Science Kits';
              case 'Math Tools':
                return l10n.subSubcategoryMathTools ?? 'Math Tools';
              case 'Language Learning':
                return l10n.subSubcategoryLanguageLearning ??
                    'Language Learning';
            }
            break;
          case 'Hobbies & Collections':
            switch (subSubKey) {
              case 'Board Games':
                return l10n.subSubcategoryBoardGamesHobby ?? 'Board Games';
              case 'Puzzles':
                return l10n.subSubcategoryPuzzlesHobby ?? 'Puzzles';
              case 'Trading Cards':
                return l10n.subSubcategoryTradingCards ?? 'Trading Cards';
              case 'Collectibles':
                return l10n.subSubcategoryCollectibles ?? 'Collectibles';
              case 'Model Kits':
                return l10n.subSubcategoryModelKits ?? 'Model Kits';
              case 'Gaming Accessories':
                return l10n.subSubcategoryGamingAccessoriesHobby ??
                    'Gaming Accessories';
            }
            break;
          case 'Musical Instruments':
            switch (subSubKey) {
              case 'String Instruments':
                return l10n.subSubcategoryStringInstruments ??
                    'String Instruments';
              case 'Wind Instruments':
                return l10n.subSubcategoryWindInstruments ?? 'Wind Instruments';
              case 'Percussion':
                return l10n.subSubcategoryPercussion ?? 'Percussion';
              case 'Electronic Instruments':
                return l10n.subSubcategoryElectronicInstruments ??
                    'Electronic Instruments';
              case 'Music Accessories':
                return l10n.subSubcategoryMusicAccessories ??
                    'Music Accessories';
              case 'Sheet Music':
                return l10n.subSubcategorySheetMusic ?? 'Sheet Music';
            }
            break;
        }
        break;
      case 'Tools & Hardware':
        switch (parentSubcategoryKey) {
          case 'Hand Tools':
            switch (subSubKey) {
              case 'Hammers':
                return l10n.subSubcategoryHammers ?? 'Hammers';
              case 'Screwdrivers':
                return l10n.subSubcategoryScrewdrivers ?? 'Screwdrivers';
              case 'Wrenches':
                return l10n.subSubcategoryWrenches ?? 'Wrenches';
              case 'Pliers':
                return l10n.subSubcategoryPliers ?? 'Pliers';
              case 'Saws':
                return l10n.subSubcategorySaws ?? 'Saws';
              case 'Chisels':
                return l10n.subSubcategoryChisels ?? 'Chisels';
              case 'Utility Knives':
                return l10n.subSubcategoryUtilityKnives ?? 'Utility Knives';
              case 'Hand Tool Sets':
                return l10n.subSubcategoryHandToolSets ?? 'Hand Tool Sets';
            }
            break;
          case 'Power Tools':
            switch (subSubKey) {
              case 'Drills':
                return l10n.subSubcategoryDrills ?? 'Drills';
              case 'Saws':
                return l10n.subSubcategoryPowerSaws ?? 'Saws';
              case 'Sanders':
                return l10n.subSubcategorySanders ?? 'Sanders';
              case 'Grinders':
                return l10n.subSubcategoryGrinders ?? 'Grinders';
              case 'Routers':
                return l10n.subSubcategoryRouters ?? 'Routers';
              case 'Nail Guns':
                return l10n.subSubcategoryNailGuns ?? 'Nail Guns';
              case 'Impact Drivers':
                return l10n.subSubcategoryImpactDrivers ?? 'Impact Drivers';
              case 'Multi-Tools':
                return l10n.subSubcategoryMultiTools ?? 'Multi-Tools';
            }
            break;
          case 'Hardware & Fasteners':
            switch (subSubKey) {
              case 'Screws':
                return l10n.subSubcategoryScrews ?? 'Screws';
              case 'Bolts & Nuts':
                return l10n.subSubcategoryBoltsNuts ?? 'Bolts & Nuts';
              case 'Nails':
                return l10n.subSubcategoryNails ?? 'Nails';
              case 'Washers':
                return l10n.subSubcategoryWashers ?? 'Washers';
              case 'Anchors':
                return l10n.subSubcategoryAnchors ?? 'Anchors';
              case 'Hinges':
                return l10n.subSubcategoryHinges ?? 'Hinges';
              case 'Handles & Knobs':
                return l10n.subSubcategoryHandlesKnobs ?? 'Handles & Knobs';
              case 'Chains':
                return l10n.subSubcategoryChains ?? 'Chains';
            }
            break;
          case 'Electrical Supplies':
            switch (subSubKey) {
              case 'Wire & Cable':
                return l10n.subSubcategoryWireCable ?? 'Wire & Cable';
              case 'Outlets & Switches':
                return l10n.subSubcategoryOutletsSwitches ??
                    'Outlets & Switches';
              case 'Circuit Breakers':
                return l10n.subSubcategoryCircuitBreakers ?? 'Circuit Breakers';
              case 'Light Fixtures':
                return l10n.subSubcategoryLightFixtures ?? 'Light Fixtures';
              case 'Electrical Tools':
                return l10n.subSubcategoryElectricalTools ?? 'Electrical Tools';
              case 'Extension Cords':
                return l10n.subSubcategoryExtensionCords ?? 'Extension Cords';
            }
            break;
          case 'Plumbing Supplies':
            switch (subSubKey) {
              case 'Pipes & Fittings':
                return l10n.subSubcategoryPipesFittings ?? 'Pipes & Fittings';
              case 'Valves':
                return l10n.subSubcategoryValves ?? 'Valves';
              case 'Faucets':
                return l10n.subSubcategoryFaucets ?? 'Faucets';
              case 'Toilet Parts':
                return l10n.subSubcategoryToiletParts ?? 'Toilet Parts';
              case 'Drain Cleaners':
                return l10n.subSubcategoryDrainCleaners ?? 'Drain Cleaners';
              case 'Pipe Tools':
                return l10n.subSubcategoryPipeTools ?? 'Pipe Tools';
              case 'Sealants':
                return l10n.subSubcategorySealants ?? 'Sealants';
            }
            break;
          case 'Building Materials':
            switch (subSubKey) {
              case 'Lumber':
                return l10n.subSubcategoryLumber ?? 'Lumber';
              case 'Drywall':
                return l10n.subSubcategoryDrywall ?? 'Drywall';
              case 'Insulation':
                return l10n.subSubcategoryInsulation ?? 'Insulation';
              case 'Roofing Materials':
                return l10n.subSubcategoryRoofingMaterials ??
                    'Roofing Materials';
              case 'Flooring':
                return l10n.subSubcategoryFlooring ?? 'Flooring';
              case 'Concrete':
                return l10n.subSubcategoryConcrete ?? 'Concrete';
              case 'Paint':
                return l10n.subSubcategoryPaint ?? 'Paint';
            }
            break;
          case 'Safety Equipment':
            switch (subSubKey) {
              case 'Work Gloves':
                return l10n.subSubcategoryWorkGlovesSafety ?? 'Work Gloves';
              case 'Safety Glasses':
                return l10n.subSubcategorySafetyGlassesSafety ??
                    'Safety Glasses';
              case 'Hard Hats':
                return l10n.subSubcategoryHardHats ?? 'Hard Hats';
              case 'Ear Protection':
                return l10n.subSubcategoryEarProtection ?? 'Ear Protection';
              case 'Respirators':
                return l10n.subSubcategoryRespirators ?? 'Respirators';
              case 'Safety Vests':
                return l10n.subSubcategorySafetyVests ?? 'Safety Vests';
              case 'First Aid Kits':
                return l10n.subSubcategoryFirstAidKitsSafety ??
                    'First Aid Kits';
            }
            break;
          case 'Measuring Tools':
            switch (subSubKey) {
              case 'Tape Measures':
                return l10n.subSubcategoryTapeMeasures ?? 'Tape Measures';
              case 'Levels':
                return l10n.subSubcategoryLevels ?? 'Levels';
              case 'Squares':
                return l10n.subSubcategorySquares ?? 'Squares';
              case 'Calipers':
                return l10n.subSubcategoryCalipers ?? 'Calipers';
              case 'Rulers':
                return l10n.subSubcategoryRulers ?? 'Rulers';
              case 'Laser Levels':
                return l10n.subSubcategoryLaserLevels ?? 'Laser Levels';
              case 'Marking Tools':
                return l10n.subSubcategoryMarkingTools ?? 'Marking Tools';
            }
            break;
          case 'Tool Storage':
            switch (subSubKey) {
              case 'Tool Boxes':
                return l10n.subSubcategoryToolBoxes ?? 'Tool Boxes';
              case 'Tool Bags':
                return l10n.subSubcategoryToolBagsStorage ?? 'Tool Bags';
              case 'Tool Chests':
                return l10n.subSubcategoryToolChests ?? 'Tool Chests';
              case 'Workshop Storage':
                return l10n.subSubcategoryWorkshopStorage ?? 'Workshop Storage';
              case 'Tool Organizers':
                return l10n.subSubcategoryToolOrganizers ?? 'Tool Organizers';
            }
            break;
        }
        break;
      case 'Pet Supplies':
        switch (parentSubcategoryKey) {
          case 'Dog Supplies':
            switch (subSubKey) {
              case 'Dog Food':
                return l10n.subSubcategoryDogFood ?? 'Dog Food';
              case 'Dog Toys':
                return l10n.subSubcategoryDogToys ?? 'Dog Toys';
              case 'Dog Beds':
                return l10n.subSubcategoryDogBeds ?? 'Dog Beds';
              case 'Leashes & Collars':
                return l10n.subSubcategoryLeashesCollars ?? 'Leashes & Collars';
              case 'Dog Clothing':
                return l10n.subSubcategoryDogClothing ?? 'Dog Clothing';
              case 'Dog Grooming':
                return l10n.subSubcategoryDogGrooming ?? 'Dog Grooming';
              case 'Dog Training':
                return l10n.subSubcategoryDogTraining ?? 'Dog Training';
              case 'Dog Health Care':
                return l10n.subSubcategoryDogHealthCare ?? 'Dog Health Care';
            }
            break;
          case 'Cat Supplies':
            switch (subSubKey) {
              case 'Cat Food':
                return l10n.subSubcategoryCatFood ?? 'Cat Food';
              case 'Cat Toys':
                return l10n.subSubcategoryCatToys ?? 'Cat Toys';
              case 'Cat Beds':
                return l10n.subSubcategoryCatBeds ?? 'Cat Beds';
              case 'Litter & Boxes':
                return l10n.subSubcategoryLitterBoxes ?? 'Litter & Boxes';
              case 'Cat Trees':
                return l10n.subSubcategoryCatTrees ?? 'Cat Trees';
              case 'Cat Grooming':
                return l10n.subSubcategoryCatGrooming ?? 'Cat Grooming';
              case 'Cat Carriers':
                return l10n.subSubcategoryCatCarriers ?? 'Cat Carriers';
              case 'Cat Health Care':
                return l10n.subSubcategoryCatHealthCare ?? 'Cat Health Care';
            }
            break;
          case 'Bird Supplies':
            switch (subSubKey) {
              case 'Bird Food':
                return l10n.subSubcategoryBirdFood ?? 'Bird Food';
              case 'Bird Cages':
                return l10n.subSubcategoryBirdCages ?? 'Bird Cages';
              case 'Bird Toys':
                return l10n.subSubcategoryBirdToys ?? 'Bird Toys';
              case 'Bird Perches':
                return l10n.subSubcategoryBirdPerches ?? 'Bird Perches';
              case 'Bird Houses':
                return l10n.subSubcategoryBirdHouses ?? 'Bird Houses';
              case 'Bird Health Care':
                return l10n.subSubcategoryBirdHealthCare ?? 'Bird Health Care';
              case 'Bird Accessories':
                return l10n.subSubcategoryBirdAccessories ?? 'Bird Accessories';
            }
            break;
          case 'Fish & Aquarium':
            switch (subSubKey) {
              case 'Fish Food':
                return l10n.subSubcategoryFishFood ?? 'Fish Food';
              case 'Aquarium Tanks':
                return l10n.subSubcategoryAquariumTanks ?? 'Aquarium Tanks';
              case 'Aquarium Filters':
                return l10n.subSubcategoryAquariumFilters ?? 'Aquarium Filters';
              case 'Aquarium Decorations':
                return l10n.subSubcategoryAquariumDecorations ??
                    'Aquarium Decorations';
              case 'Water Treatment':
                return l10n.subSubcategoryWaterTreatment ?? 'Water Treatment';
              case 'Aquarium Lighting':
                return l10n.subSubcategoryAquariumLighting ??
                    'Aquarium Lighting';
              case 'Fish Health Care':
                return l10n.subSubcategoryFishHealthCare ?? 'Fish Health Care';
            }
            break;
          case 'Small Animal Supplies':
            switch (subSubKey) {
              case 'Small Animal Food':
                return l10n.subSubcategorySmallAnimalFood ??
                    'Small Animal Food';
              case 'Cages & Habitats':
                return l10n.subSubcategoryCagesHabitats ?? 'Cages & Habitats';
              case 'Small Animal Toys':
                return l10n.subSubcategorySmallAnimalToys ??
                    'Small Animal Toys';
              case 'Bedding':
                return l10n.subSubcategoryBedding ?? 'Bedding';
              case 'Water Bottles':
                return l10n.subSubcategoryWaterBottles ?? 'Water Bottles';
              case 'Exercise Equipment':
                return l10n.subSubcategoryExerciseEquipmentPet ??
                    'Exercise Equipment';
            }
            break;
          case 'Pet Food & Treats':
            switch (subSubKey) {
              case 'Dry Food':
                return l10n.subSubcategoryDryFood ?? 'Dry Food';
              case 'Wet Food':
                return l10n.subSubcategoryWetFood ?? 'Wet Food';
              case 'Treats & Snacks':
                return l10n.subSubcategoryTreatsSnacks ?? 'Treats & Snacks';
              case 'Supplements':
                return l10n.subSubcategorySupplementsPet ?? 'Supplements';
              case 'Special Diet Food':
                return l10n.subSubcategorySpecialDietFood ??
                    'Special Diet Food';
              case 'Organic Food':
                return l10n.subSubcategoryOrganicFood ?? 'Organic Food';
            }
            break;
          case 'Pet Care & Health':
            switch (subSubKey) {
              case 'Flea & Tick Control':
                return l10n.subSubcategoryFleaTickControl ??
                    'Flea & Tick Control';
              case 'Vitamins & Supplements':
                return l10n.subSubcategoryVitaminsSupplementsPet ??
                    'Vitamins & Supplements';
              case 'First Aid':
                return l10n.subSubcategoryFirstAidPet ?? 'First Aid';
              case 'Dental Care':
                return l10n.subSubcategoryDentalCarePet ?? 'Dental Care';
              case 'Skin & Coat Care':
                return l10n.subSubcategorySkinCoatCare ?? 'Skin & Coat Care';
              case 'Health Monitoring':
                return l10n.subSubcategoryHealthMonitoringPet ??
                    'Health Monitoring';
            }
            break;
          case 'Pet Accessories':
            switch (subSubKey) {
              case 'Pet Carriers':
                return l10n.subSubcategoryPetCarriers ?? 'Pet Carriers';
              case 'Pet Strollers':
                return l10n.subSubcategoryPetStrollers ?? 'Pet Strollers';
              case 'Pet Gates':
                return l10n.subSubcategoryPetGates ?? 'Pet Gates';
              case 'Travel Accessories':
                return l10n.subSubcategoryTravelAccessoriesPet ??
                    'Travel Accessories';
              case 'Pet ID Tags':
                return l10n.subSubcategoryPetIDTags ?? 'Pet ID Tags';
              case 'Cleanup Supplies':
                return l10n.subSubcategoryCleanupSupplies ?? 'Cleanup Supplies';
            }
            break;
          case 'Pet Training':
            switch (subSubKey) {
              case 'Training Treats':
                return l10n.subSubcategoryTrainingTreats ?? 'Training Treats';
              case 'Training Tools':
                return l10n.subSubcategoryTrainingTools ?? 'Training Tools';
              case 'Clickers':
                return l10n.subSubcategoryClickers ?? 'Clickers';
              case 'Training Pads':
                return l10n.subSubcategoryTrainingPads ?? 'Training Pads';
              case 'Behavioral Aids':
                return l10n.subSubcategoryBehavioralAids ?? 'Behavioral Aids';
            }
            break;
        }
        break;
      case 'Automotive':
        switch (parentSubcategoryKey) {
          case 'Car Parts & Accessories':
            switch (subSubKey) {
              case 'Engine Parts':
                return l10n.subSubcategoryEngineParts ?? 'Engine Parts';
              case 'Brake Parts':
                return l10n.subSubcategoryBrakeParts ?? 'Brake Parts';
              case 'Suspension Parts':
                return l10n.subSubcategorySuspensionParts ?? 'Suspension Parts';
              case 'Exhaust Parts':
                return l10n.subSubcategoryExhaustParts ?? 'Exhaust Parts';
              case 'Electrical Parts':
                return l10n.subSubcategoryElectricalPartsAuto ??
                    'Electrical Parts';
              case 'Body Parts':
                return l10n.subSubcategoryBodyParts ?? 'Body Parts';
              case 'Interior Accessories':
                return l10n.subSubcategoryInteriorAccessoriesAuto ??
                    'Interior Accessories';
              case 'Exterior Accessories':
                return l10n.subSubcategoryExteriorAccessories ??
                    'Exterior Accessories';
            }
            break;
          case 'Car Care & Maintenance':
            switch (subSubKey) {
              case 'Car Wash Products':
                return l10n.subSubcategoryCarWashProducts ??
                    'Car Wash Products';
              case 'Wax & Polish':
                return l10n.subSubcategoryWaxPolish ?? 'Wax & Polish';
              case 'Interior Cleaners':
                return l10n.subSubcategoryInteriorCleaners ??
                    'Interior Cleaners';
              case 'Engine Cleaners':
                return l10n.subSubcategoryEngineCleaners ?? 'Engine Cleaners';
              case 'Tire Care':
                return l10n.subSubcategoryTireCare ?? 'Tire Care';
              case 'Glass Cleaners':
                return l10n.subSubcategoryGlassCleaners ?? 'Glass Cleaners';
              case 'Motor Oil':
                return l10n.subSubcategoryMotorOil ?? 'Motor Oil';
              case 'Car Cleaners':
                return l10n.subSubcategoryCarCleaners ?? 'Car Cleaners';
              case 'Maintenance Tools':
                return l10n.subSubcategoryMaintenanceTools ?? 'Maintenance Tools';
              case 'Fluids':
                return l10n.subSubcategoryFluidsAuto ?? 'Fluids';
            }
            break;
          case 'Tires & Wheels':
            switch (subSubKey) {
              case 'Summer Tires':
                return l10n.subSubcategorySummerTires ?? 'Summer Tires';
              case 'Winter Tires':
                return l10n.subSubcategoryWinterTires ?? 'Winter Tires';
              case 'All-Season Tires':
                return l10n.subSubcategoryAllSeasonTires ?? 'All-Season Tires';
              case 'Performance Tires':
                return l10n.subSubcategoryPerformanceTires ??
                    'Performance Tires';
              case 'Alloy Wheels':
                return l10n.subSubcategoryAlloyWheels ?? 'Alloy Wheels';
              case 'Steel Wheels':
                return l10n.subSubcategorySteelWheels ?? 'Steel Wheels';
              case 'Wheel Accessories':
                return l10n.subSubcategoryWheelAccessories ??
                    'Wheel Accessories';
              case 'Tires':
                return l10n.subSubcategoryTires ?? 'Tires';
              case 'Wheels':
                return l10n.subSubcategoryWheels ?? 'Wheels';
              case 'Tire Accessories':
                return l10n.subSubcategoryTireAccessories ?? 'Tire Accessories';
              case 'Wheel Covers':
                return l10n.subSubcategoryWheelCovers ?? 'Wheel Covers';
              case 'Tire Pressure Monitors':
                return l10n.subSubcategoryTirePressureMonitors ?? 'Tire Pressure Monitors';
            }
            break;
          case 'Car Electronics':
            switch (subSubKey) {
              case 'Car Stereos':
                return l10n.subSubcategoryCarStereos ?? 'Car Stereos';
              case 'GPS Navigation':
                return l10n.subSubcategoryGPSNavigation ?? 'GPS Navigation';
              case 'Dash Cameras':
                return l10n.subSubcategoryDashCameras ?? 'Dash Cameras';
              case 'Car Alarms':
                return l10n.subSubcategoryCarAlarms ?? 'Car Alarms';
              case 'Car Speakers':
                return l10n.subSubcategoryCarSpeakers ?? 'Car Speakers';
              case 'Car Amplifiers':
                return l10n.subSubcategoryCarAmplifiers ?? 'Car Amplifiers';
              case 'Car Audio':
                return l10n.subSubcategoryCarAudio ?? 'Car Audio';
              case 'GPS & Navigation':
                return l10n.subSubcategoryGPSAndNavigation ?? 'GPS & Navigation';
              case 'Dash Cams':
                return l10n.subSubcategoryDashCams ?? 'Dash Cams';
              case 'Bluetooth Adapters':
                return l10n.subSubcategoryBluetoothAdapters ?? 'Bluetooth Adapters';
              case 'Backup Cameras':
                return l10n.subSubcategoryBackupCameras ?? 'Backup Cameras';
            }
            break;
          case 'Motorcycle Parts':
            switch (subSubKey) {
              case 'Motorcycle Engines':
                return l10n.subSubcategoryMotorcycleEngines ??
                    'Motorcycle Engines';
              case 'Motorcycle Brakes':
                return l10n.subSubcategoryMotorcycleBrakes ??
                    'Motorcycle Brakes';
              case 'Motorcycle Tires':
                return l10n.subSubcategoryMotorcycleTires ?? 'Motorcycle Tires';
              case 'Motorcycle Lights':
                return l10n.subSubcategoryMotorcycleLights ??
                    'Motorcycle Lights';
              case 'Motorcycle Exhaust':
                return l10n.subSubcategoryMotorcycleExhaust ??
                    'Motorcycle Exhaust';
              case 'Motorcycle Body Parts':
                return l10n.subSubcategoryMotorcycleBodyParts ??
                    'Motorcycle Body Parts';
              case 'Motorcycle Parts':
                return l10n.subSubcategoryMotorcyclePartsGeneral ?? 'Motorcycle Parts';
              case 'Motorcycle Accessories':
                return l10n.subSubcategoryMotorcycleAccessoriesGeneral ?? 'Motorcycle Accessories';
              case 'Motorcycle Gear':
                return l10n.subSubcategoryMotorcycleGear ?? 'Motorcycle Gear';
              case 'Helmets':
                return l10n.subSubcategoryHelmets ?? 'Helmets';
              case 'Protective Clothing':
                return l10n.subSubcategoryProtectiveClothing ?? 'Protective Clothing';
            }
            break;
          case 'Motorcycle Accessories':
            switch (subSubKey) {
              case 'Motorcycle Helmets':
                return l10n.subSubcategoryMotorcycleHelmets ??
                    'Motorcycle Helmets';
              case 'Motorcycle Gloves':
                return l10n.subSubcategoryMotorcycleGloves ??
                    'Motorcycle Gloves';
              case 'Motorcycle Jackets':
                return l10n.subSubcategoryMotorcycleJackets ??
                    'Motorcycle Jackets';
              case 'Motorcycle Boots':
                return l10n.subSubcategoryMotorcycleBoots ?? 'Motorcycle Boots';
              case 'Motorcycle Bags':
                return l10n.subSubcategoryMotorcycleBags ?? 'Motorcycle Bags';
              case 'Motorcycle Tools':
                return l10n.subSubcategoryMotorcycleTools ?? 'Motorcycle Tools';
            }
            break;
          case 'Car Tools':
            switch (subSubKey) {
              case 'Hand Tools':
                return l10n.subSubcategoryHandToolsAuto ?? 'Hand Tools';
              case 'Power Tools':
                return l10n.subSubcategoryPowerToolsAuto ?? 'Power Tools';
              case 'Diagnostic Tools':
                return l10n.subSubcategoryDiagnosticTools ?? 'Diagnostic Tools';
              case 'Lifting Equipment':
                return l10n.subSubcategoryLiftingEquipment ??
                    'Lifting Equipment';
              case 'Measuring Tools':
                return l10n.subSubcategoryMeasuringToolsAuto ??
                    'Measuring Tools';
            }
            break;
          case 'Oils & Fluids':
            switch (subSubKey) {
              case 'Engine Oil':
                return l10n.subSubcategoryEngineOil ?? 'Engine Oil';
              case 'Transmission Fluid':
                return l10n.subSubcategoryTransmissionFluid ??
                    'Transmission Fluid';
              case 'Brake Fluid':
                return l10n.subSubcategoryBrakeFluid ?? 'Brake Fluid';
              case 'Coolant':
                return l10n.subSubcategoryCoolant ?? 'Coolant';
              case 'Power Steering Fluid':
                return l10n.subSubcategoryPowerSteeringFluid ??
                    'Power Steering Fluid';
              case 'Windshield Washer Fluid':
                return l10n.subSubcategoryWindshieldWasherFluid ??
                    'Windshield Washer Fluid';
            }
            break;
          case 'Car Parts & Components':
            switch (subSubKey) {
              case 'Engine Parts':
                return l10n.subSubcategoryEngineParts ?? 'Engine Parts';
              case 'Brake Components':
                return l10n.subSubcategoryBrakeComponents ?? 'Brake Components';
              case 'Suspension Parts':
                return l10n.subSubcategorySuspensionParts ?? 'Suspension Parts';
              case 'Transmission Parts':
                return l10n.subSubcategoryTransmissionParts ?? 'Transmission Parts';
              case 'Exhaust Systems':
                return l10n.subSubcategoryExhaustSystems ?? 'Exhaust Systems';
              case 'Filters':
                return l10n.subSubcategoryFiltersAuto ?? 'Filters';
              case 'Belts & Hoses':
                return l10n.subSubcategoryBeltsHoses ?? 'Belts & Hoses';
            }
            break;
          case 'Interior Accessories':
            switch (subSubKey) {
              case 'Seat Covers':
                return l10n.subSubcategorySeatCovers ?? 'Seat Covers';
              case 'Floor Mats':
                return l10n.subSubcategoryFloorMats ?? 'Floor Mats';
              case 'Steering Wheel Covers':
                return l10n.subSubcategorySteeringWheelCovers ?? 'Steering Wheel Covers';
              case 'Air Fresheners':
                return l10n.subSubcategoryAirFresheners ?? 'Air Fresheners';
              case 'Interior Organizers':
                return l10n.subSubcategoryInteriorOrganizers ?? 'Interior Organizers';
              case 'Sunshades':
                return l10n.subSubcategorySunshades ?? 'Sunshades';
            }
            break;
          case 'Exterior Accessories':
            switch (subSubKey) {
              case 'Car Covers':
                return l10n.subSubcategoryCarCovers ?? 'Car Covers';
              case 'Roof Racks':
                return l10n.subSubcategoryRoofRacks ?? 'Roof Racks';
              case 'Running Boards':
                return l10n.subSubcategoryRunningBoards ?? 'Running Boards';
              case 'Mud Flaps':
                return l10n.subSubcategoryMudFlaps ?? 'Mud Flaps';
              case 'License Plate Frames':
                return l10n.subSubcategoryLicensePlateFrames ?? 'License Plate Frames';
              case 'Decals':
                return l10n.subSubcategoryDecals ?? 'Decals';
            }
            break;
          case 'Tools & Equipment':
            switch (subSubKey) {
              case 'Jump Starters':
                return l10n.subSubcategoryJumpStarters ?? 'Jump Starters';
              case 'Tire Gauges':
                return l10n.subSubcategoryTireGauges ?? 'Tire Gauges';
              case 'Mechanics Tools':
                return l10n.subSubcategoryMechanicsTools ?? 'Mechanics Tools';
              case 'Car Jacks':
                return l10n.subSubcategoryCarJacks ?? 'Car Jacks';
              case 'Emergency Kits':
                return l10n.subSubcategoryEmergencyKitsAuto ?? 'Emergency Kits';
              case 'Diagnostic Tools':
                return l10n.subSubcategoryDiagnosticTools ?? 'Diagnostic Tools';
            }
            break;
        }
        break;
      case 'Health & Wellness':
        switch (parentSubcategoryKey) {
          case 'Vitamins & Supplements':
            switch (subSubKey) {
              case 'Multivitamins':
                return l10n.subSubcategoryMultivitamins ?? 'Multivitamins';
              case 'Vitamin C':
                return l10n.subSubcategoryVitaminC ?? 'Vitamin C';
              case 'Vitamin D':
                return l10n.subSubcategoryVitaminD ?? 'Vitamin D';
              case 'Calcium':
                return l10n.subSubcategoryCalcium ?? 'Calcium';
              case 'Iron':
                return l10n.subSubcategoryIron ?? 'Iron';
              case 'Omega-3':
                return l10n.subSubcategoryOmega3 ?? 'Omega-3';
              case 'Protein Supplements':
                return l10n.subSubcategoryProteinSupplements ??
                    'Protein Supplements';
              case 'Probiotics':
                return l10n.subSubcategoryProbiotics ?? 'Probiotics';
              case 'B Vitamins':
                return l10n.subSubcategoryBVitamins ?? 'B Vitamins';
              case 'Herbal Supplements':
                return l10n.subSubcategoryHerbalSupplements ?? 'Herbal Supplements';
            }
            break;
          case 'Medical Devices':
            switch (subSubKey) {
              case 'Blood Pressure Monitors':
                return l10n.subSubcategoryBloodPressureMonitors ??
                    'Blood Pressure Monitors';
              case 'Thermometers':
                return l10n.subSubcategoryThermometers ?? 'Thermometers';
              case 'Glucose Meters':
                return l10n.subSubcategoryGlucoseMeters ?? 'Glucose Meters';
              case 'Pulse Oximeters':
                return l10n.subSubcategoryPulseOximeters ?? 'Pulse Oximeters';
              case 'Nebulizers':
                return l10n.subSubcategoryNebulizers ?? 'Nebulizers';
              case 'Stethoscopes':
                return l10n.subSubcategoryStethoscopes ?? 'Stethoscopes';
            }
            break;
          case 'First Aid':
            switch (subSubKey) {
              case 'Bandages':
                return l10n.subSubcategoryBandages ?? 'Bandages';
              case 'Antiseptics':
                return l10n.subSubcategoryAntiseptics ?? 'Antiseptics';
              case 'Pain Relief':
                return l10n.subSubcategoryPainRelief ?? 'Pain Relief';
              case 'Wound Care':
                return l10n.subSubcategoryWoundCare ?? 'Wound Care';
              case 'First Aid Kits':
                return l10n.subSubcategoryFirstAidKits ?? 'First Aid Kits';
              case 'Emergency Supplies':
                return l10n.subSubcategoryEmergencySupplies ??
                    'Emergency Supplies';
            }
            break;
          case 'Personal Health':
            switch (subSubKey) {
              case 'Weight Management':
                return l10n.subSubcategoryWeightManagement ??
                    'Weight Management';
              case 'Digestive Health':
                return l10n.subSubcategoryDigestiveHealth ?? 'Digestive Health';
              case 'Heart Health':
                return l10n.subSubcategoryHeartHealth ?? 'Heart Health';
              case 'Joint Health':
                return l10n.subSubcategoryJointHealth ?? 'Joint Health';
              case 'Mental Health':
                return l10n.subSubcategoryMentalHealth ?? 'Mental Health';
              case 'Sleep Aids':
                return l10n.subSubcategorySleepAids ?? 'Sleep Aids';
              case 'Energy Boosters':
                return l10n.subSubcategoryEnergyBoosters ?? 'Energy Boosters';
            }
            break;
          case 'Mobility Aids':
            switch (subSubKey) {
              case 'Wheelchairs':
                return l10n.subSubcategoryWheelchairs ?? 'Wheelchairs';
              case 'Walkers':
                return l10n.subSubcategoryWalkers ?? 'Walkers';
              case 'Crutches':
                return l10n.subSubcategoryCrutches ?? 'Crutches';
              case 'Canes':
                return l10n.subSubcategoryCanes ?? 'Canes';
              case 'Mobility Scooters':
                return l10n.subSubcategoryMobilityScooters ??
                    'Mobility Scooters';
              case 'Bath Safety':
                return l10n.subSubcategoryBathSafety ?? 'Bath Safety';
            }
            break;
          case 'Alternative Medicine':
            switch (subSubKey) {
              case 'Herbal Remedies':
                return l10n.subSubcategoryHerbalRemedies ?? 'Herbal Remedies';
              case 'Essential Oils':
                return l10n.subSubcategoryEssentialOils ?? 'Essential Oils';
              case 'Aromatherapy':
                return l10n.subSubcategoryAromatherapy ?? 'Aromatherapy';
              case 'Homeopathy':
                return l10n.subSubcategoryHomeopathy ?? 'Homeopathy';
              case 'Traditional Medicine':
                return l10n.subSubcategoryTraditionalMedicine ??
                    'Traditional Medicine';
              case 'Natural Supplements':
                return l10n.subSubcategoryNaturalSupplements ??
                    'Natural Supplements';
              case 'Massage Tools':
                return l10n.subSubcategoryMassageTools ?? 'Massage Tools';
              case 'Acupuncture':
                return l10n.subSubcategoryAcupuncture ?? 'Acupuncture';
              case 'Natural Remedies':
                return l10n.subSubcategoryNaturalRemedies ?? 'Natural Remedies';
            }
            break;
          case 'Fitness & Nutrition':
            switch (subSubKey) {
              case 'Protein Powders':
                return l10n.subSubcategoryProteinPowders ?? 'Protein Powders';
              case 'Pre-Workout':
                return l10n.subSubcategoryPreWorkout ?? 'Pre-Workout';
              case 'Post-Workout':
                return l10n.subSubcategoryPostWorkout ?? 'Post-Workout';
              case 'Fat Burners':
                return l10n.subSubcategoryFatBurners ?? 'Fat Burners';
              case 'Meal Replacements':
                return l10n.subSubcategoryMealReplacements ??
                    'Meal Replacements';
              case 'Sports Nutrition':
                return l10n.subSubcategorySportsNutrition ?? 'Sports Nutrition';
              case 'Healthy Snacks':
                return l10n.subSubcategoryHealthySnacks ?? 'Healthy Snacks';
            }
            break;
          case 'Sexual Health':
            switch (subSubKey) {
              case 'Contraceptives':
                return l10n.subSubcategoryContraceptives ?? 'Contraceptives';
              case 'Pregnancy Tests':
                return l10n.subSubcategoryPregnancyTests ?? 'Pregnancy Tests';
              case 'Fertility Products':
                return l10n.subSubcategoryFertilityProducts ??
                    'Fertility Products';
              case 'Personal Lubricants':
                return l10n.subSubcategoryPersonalLubricants ??
                    'Personal Lubricants';
              case 'Enhancement Products':
                return l10n.subSubcategoryEnhancementProducts ??
                    'Enhancement Products';
            }
            break;
          case 'Medical Equipment':
            switch (subSubKey) {
              case 'Blood Pressure Monitors':
                return l10n.subSubcategoryBloodPressureMonitors ?? 'Blood Pressure Monitors';
              case 'Thermometers':
                return l10n.subSubcategoryThermometers ?? 'Thermometers';
              case 'Glucose Meters':
                return l10n.subSubcategoryGlucoseMeters ?? 'Glucose Meters';
              case 'Pulse Oximeters':
                return l10n.subSubcategoryPulseOximeters ?? 'Pulse Oximeters';
              case 'Stethoscopes':
                return l10n.subSubcategoryStethoscopes ?? 'Stethoscopes';
              case 'Medical Scales':
                return l10n.subSubcategoryMedicalScales ?? 'Medical Scales';
            }
            break;
          case 'First Aid & Safety':
            switch (subSubKey) {
              case 'First Aid Kits':
                return l10n.subSubcategoryFirstAidKits ?? 'First Aid Kits';
              case 'Bandages':
                return l10n.subSubcategoryBandages ?? 'Bandages';
              case 'Antiseptics':
                return l10n.subSubcategoryAntiseptics ?? 'Antiseptics';
              case 'Pain Relief':
                return l10n.subSubcategoryPainRelief ?? 'Pain Relief';
              case 'Emergency Supplies':
                return l10n.subSubcategoryEmergencySupplies ?? 'Emergency Supplies';
              case 'Safety Equipment':
                return l10n.subSubcategorySafetyEquipment ?? 'Safety Equipment';
            }
            break;
          case 'Fitness & Exercise Equipment':
            switch (subSubKey) {
              case 'Home Gym Equipment':
                return l10n.subSubcategoryHomeGymEquipment ?? 'Home Gym Equipment';
              case 'Cardio Machines':
                return l10n.subSubcategoryCardioMachines ?? 'Cardio Machines';
              case 'Weights & Dumbbells':
                return l10n.subSubcategoryWeightsDumbbells ?? 'Weights & Dumbbells';
              case 'Resistance Bands':
                return l10n.subSubcategoryResistanceBands ?? 'Resistance Bands';
              case 'Yoga Mats':
                return l10n.subSubcategoryYogaMats ?? 'Yoga Mats';
              case 'Exercise Bikes':
                return l10n.subSubcategoryExerciseBikes ?? 'Exercise Bikes';
            }
            break;
          case 'Health Monitoring':
            switch (subSubKey) {
              case 'Fitness Trackers':
                return l10n.subSubcategoryFitnessTrackers ?? 'Fitness Trackers';
              case 'Smart Scales':
                return l10n.subSubcategorySmartScales ?? 'Smart Scales';
              case 'Heart Rate Monitors':
                return l10n.subSubcategoryHeartRateMonitors ?? 'Heart Rate Monitors';
              case 'Sleep Trackers':
                return l10n.subSubcategorySleepTrackers ?? 'Sleep Trackers';
              case 'Health Apps':
                return l10n.subSubcategoryHealthApps ?? 'Health Apps';
            }
            break;
          case 'Mobility & Daily Living':
            switch (subSubKey) {
              case 'Mobility Aids':
                return l10n.subSubcategoryMobilityAidsGeneral ?? 'Mobility Aids';
              case 'Grab Bars':
                return l10n.subSubcategoryGrabBars ?? 'Grab Bars';
              case 'Bath Safety':
                return l10n.subSubcategoryBathSafety ?? 'Bath Safety';
              case 'Seat Cushions':
                return l10n.subSubcategorySeatCushions ?? 'Seat Cushions';
              case 'Daily Living Aids':
                return l10n.subSubcategoryDailyLivingAids ?? 'Daily Living Aids';
            }
            break;
          case 'Personal Care':
            switch (subSubKey) {
              case 'Oral Care':
                return l10n.subSubcategoryOralCare ?? 'Oral Care';
              case 'Incontinence Care':
                return l10n.subSubcategoryIncontinenceCare ?? 'Incontinence Care';
              case 'Hearing Aids':
                return l10n.subSubcategoryHearingAids ?? 'Hearing Aids';
              case 'Vision Care':
                return l10n.subSubcategoryVisionCare ?? 'Vision Care';
              case 'Skin Care':
                return l10n.subSubcategorySkinCareHealth ?? 'Skin Care';
            }
            break;
        }
        break;
    }
    return subSubKey;
  }

  static const List<Map<String, String>> kBuyerCategories = [
    {'key': 'Women', 'image': 'women.jpg'},
    {'key': 'Men', 'image': 'men.jpg'},
    {'key': 'Mother & Child', 'image': 'mother_child.jpg'},
    {'key': 'Home & Furniture', 'image': 'home_furniture.jpg'},
    {'key': 'Electronics', 'image': 'electronics.jpg'},
    {'key': 'Books, Stationery & Hobby', 'image': 'books_stationery_hobby.jpg'},
    {'key': 'Flowers & Gifts', 'image': 'flowers_gifts.jpg'},
    {'key': 'Sports & Outdoor', 'image': 'sports_outdoor.jpg'},
    {'key': 'Tools & Hardware', 'image': 'tools_hardware.jpg'},
    {'key': 'Pet Supplies', 'image': 'pet_supplies.jpg'},
    {'key': 'Automotive', 'image': 'automotive.jpg'},
    {'key': 'Health & Wellness', 'image': 'health_wellness.jpg'},
  ];

  /// Buyer-focused subcategories structure
  static const Map<String, List<String>> kBuyerSubcategories = {
    'Women': [
      'Fashion',
      'Shoes',
      'Accessories',
      'Bags',
      'Self Care',
    ],
    'Men': [
      'Fashion',
      'Shoes',
      'Accessories',
      'Bags',
      'Self Care',
    ],
    'Mother & Child': [
      'Baby Clothing',
      'Kids Clothing',
      'Kids Footwear',
      'Toys & Games',
      'Baby Care',
      'Maternity',
      'Strollers & Car Seats',
      'Feeding & Nursing',
      'Safety & Security',
      'Educational',
    ],
    'Home & Furniture': [
      'Living Room Furniture',
      'Bedroom Furniture',
      'Kitchen & Dining',
      'Bathroom',
      'Home Decor',
      'Lighting',
      'Storage & Organization',
      'Textiles & Soft Furnishing',
      'Garden & Outdoor',
    ],
    'Electronics': [
      'Smartphones & Accessories',
      'Computers & Laptops',
      'TVs & Home Entertainment',
      'Audio Equipment',
      'Gaming',
      'Smart Home & IoT',
      'Cameras & Photography',
      'Wearable Tech',
      'Home Appliances',
      'Personal Care Electronics',
    ],
    'Books, Stationery & Hobby': [
      'Books & Literature',
      'Office & School Supplies',
      'Art & Craft Supplies',
      'Writing Instruments',
      'Paper Products',
      'Educational Materials',
      'Hobbies & Collections',
      'Musical Instruments',
    ],
    'Flowers & Gifts': [
      'Bouquets & Arrangements',
      'Potted Plants',
      'Gift Arrangements',
      'Flower Accessories',
      'Wreaths & Centerpieces',
    ],
    'Sports & Outdoor': [
      'Fitness & Exercise',
      'Sports',
      'Water Sports',
      'Outdoor & Camping',
      'Winter Sports',
      'Cycling',
      'Running & Athletics',
      'Sports Accessories',
      'Sportswear',
    ],
    'Tools & Hardware': [
      'Hand Tools',
      'Power Tools',
      'Hardware & Fasteners',
      'Electrical Supplies',
      'Plumbing Supplies',
      'Building Materials',
      'Safety Equipment',
      'Measuring Tools',
      'Tool Storage',
    ],
    'Pet Supplies': [
      'Dog Supplies',
      'Cat Supplies',
      'Bird Supplies',
      'Fish & Aquarium',
      'Small Animal Supplies',
      'Pet Food & Treats',
      'Pet Care & Health',
      'Pet Accessories',
      'Pet Training',
    ],
    'Automotive': [
      'Car Parts & Components',
      'Car Electronics',
      'Car Care & Maintenance',
      'Tires & Wheels',
      'Interior Accessories',
      'Exterior Accessories',
      'Tools & Equipment',
      'Motorcycle Parts',
    ],
    'Health & Wellness': [
      'Vitamins & Supplements',
      'Medical Equipment',
      'First Aid & Safety',
      'Fitness & Exercise Equipment',
      'Health Monitoring',
      'Mobility & Daily Living',
      'Alternative Medicine',
      'Personal Care',
    ],
  };

  /// Buyer-focused sub-subcategories structure
  static final Map<String, Map<String, List<String>>> kBuyerSubSubcategories = {
    'Women': {
      'Fashion': [
        'Dresses',
        'Tops & Shirts',
        'Bottoms',
        'Outerwear',
        'Underwear & Sleepwear',
        'Swimwear',
        'Activewear',
        'Suits & Formal',
        'Traditional & Cultural',
      ],
      'Shoes': [
        'Sneakers & Athletic',
        'Casual Shoes',
        'Formal Shoes',
        'Boots',
        'Sandals & Flip-Flops',
        'Slippers',
        'Specialized Footwear',
      ],
      'Accessories': [
        'Jewelry',
        'Watches',
        'Belts',
        'Hats & Caps',
        'Scarves & Wraps',
        'Sunglasses & Eyewear',
        'Gloves',
        'Hair Accessories',
        'Other Accessories',
      ],
      'Bags': [
        'Handbags',
        'Backpacks',
        'Travel Luggage',
        'Sports & Gym Bags',
        'Wallets & Small Accessories',
        'Specialty Bags',
      ],
      'Self Care': [
        'Skincare',
        'Makeup',
        'Haircare',
        'Fragrances',
        'Personal Hygiene',
        'Nail Care',
        'Body Care',
        'Oral Care',
        'Beauty Tools & Accessories',
      ],
    },
    'Men': {
      'Fashion': [
        'Tops & Shirts',
        'Bottoms',
        'Outerwear',
        'Underwear & Sleepwear',
        'Swimwear',
        'Activewear',
        'Suits & Formal',
        'Traditional & Cultural',
      ],
      'Shoes': [
        'Sneakers & Athletic',
        'Casual Shoes',
        'Formal Shoes',
        'Boots',
        'Sandals & Flip-Flops',
        'Slippers',
        'Specialized Footwear',
      ],
      'Accessories': [
        'Watches',
        'Belts',
        'Hats & Caps',
        'Sunglasses & Eyewear',
        'Gloves',
        'Other Accessories',
      ],
      'Bags': [
        'Backpacks',
        'Travel Luggage',
        'Briefcases & Business Bags',
        'Sports & Gym Bags',
        'Wallets & Small Accessories',
        'Specialty Bags',
      ],
      'Self Care': [
        'Personal Hygiene',
        'Haircare',
        'Fragrances',
        'Body Care',
        'Oral Care',
        'Beauty Tools & Accessories',
      ],
    },
    // For other categories, use the existing kSubSubcategories structure
    'Mother & Child': _getSubSubcategories('Mother & Child'),
    'Home & Furniture': _getSubSubcategories('Home & Furniture'),
    'Electronics': _getSubSubcategories('Electronics'),
    'Books, Stationery & Hobby':
        _getSubSubcategories('Books, Stationery & Hobby'),
    'Flowers & Gifts': _getSubSubcategories('Flowers & Gifts'),
    'Sports & Outdoor': _getSubSubcategories('Sports & Outdoor'),
    'Tools & Hardware': _getSubSubcategories('Tools & Hardware'),
    'Pet Supplies': _getSubSubcategories('Pet Supplies'),
    'Automotive': _getSubSubcategories('Automotive'),
    'Health & Wellness': _getSubSubcategories('Health & Wellness'),
  };

  static Map<String, List<String>> _getSubSubcategories(String category) {
    return kSubSubcategories[category] ?? {};
  }

  /// Mapping from buyer category/subcategory to original product categories for filtering
  static const Map<String, Map<String, String>> kBuyerToProductCategoryMapping =
      {
    'Women': {
      'Fashion': 'Clothing & Fashion',
      'Shoes': 'Footwear',
      'Accessories': 'Accessories',
      'Bags': 'Bags & Luggage',
      'Self Care': 'Beauty & Personal Care',
    },
    'Men': {
      'Fashion': 'Clothing & Fashion',
      'Shoes': 'Footwear',
      'Accessories': 'Accessories',
      'Bags': 'Bags & Luggage',
      'Self Care': 'Beauty & Personal Care',
    },
    'Mother & Child': {
      'Baby Clothing': 'Mother & Child',
      'Kids Clothing': 'Mother & Child',
      'Kids Footwear': 'Mother & Child',
      'Toys & Games': 'Mother & Child',
      'Baby Care': 'Mother & Child',
      'Maternity': 'Mother & Child',
      'Strollers & Car Seats': 'Mother & Child',
      'Feeding & Nursing': 'Mother & Child',
      'Safety & Security': 'Mother & Child',
      'Educational': 'Mother & Child',
    },
    'Home & Furniture': {
      'Living Room Furniture': 'Home & Furniture',
      'Bedroom Furniture': 'Home & Furniture',
      'Kitchen & Dining': 'Home & Furniture',
      'Bathroom': 'Home & Furniture',
      'Home Decor': 'Home & Furniture',
      'Lighting': 'Home & Furniture',
      'Storage & Organization': 'Home & Furniture',
      'Textiles & Soft Furnishing': 'Home & Furniture',
      'Garden & Outdoor': 'Home & Furniture',
    },
    'Electronics': {
      'Smartphones & Accessories': 'Electronics',
      'Computers & Laptops': 'Electronics',
      'TVs & Home Entertainment': 'Electronics',
      'Audio Equipment': 'Electronics',
      'Gaming': 'Electronics',
      'Smart Home & IoT': 'Electronics',
      'Cameras & Photography': 'Electronics',
      'Wearable Tech': 'Electronics',
      'Home Appliances': 'Electronics',
      'Personal Care Electronics': 'Electronics',
    },
    'Books, Stationery & Hobby': {
      'Books & Literature': 'Books, Stationery & Hobby',
      'Office & School Supplies': 'Books, Stationery & Hobby',
      'Art & Craft Supplies': 'Books, Stationery & Hobby',
      'Writing Instruments': 'Books, Stationery & Hobby',
      'Paper Products': 'Books, Stationery & Hobby',
      'Educational Materials': 'Books, Stationery & Hobby',
      'Hobbies & Collections': 'Books, Stationery & Hobby',
      'Musical Instruments': 'Books, Stationery & Hobby',
    },
    'Flowers & Gifts': {
      'Bouquets & Arrangements': 'Flowers & Gifts',
      'Potted Plants': 'Flowers & Gifts',
      'Gift Arrangements': 'Flowers & Gifts',
      'Flower Accessories': 'Flowers & Gifts',
      'Wreaths & Centerpieces': 'Flowers & Gifts',
    },
    'Sports & Outdoor': {
      'Fitness & Exercise': 'Sports & Outdoor',
      'Sports': 'Sports & Outdoor',
      'Water Sports': 'Sports & Outdoor',
      'Outdoor & Camping': 'Sports & Outdoor',
      'Winter Sports': 'Sports & Outdoor',
      'Cycling': 'Sports & Outdoor',
      'Running & Athletics': 'Sports & Outdoor',
      'Sports Accessories': 'Sports & Outdoor',
      'Sportswear': 'Sports & Outdoor',
    },
    'Tools & Hardware': {
      'Hand Tools': 'Tools & Hardware',
      'Power Tools': 'Tools & Hardware',
      'Hardware & Fasteners': 'Tools & Hardware',
      'Electrical Supplies': 'Tools & Hardware',
      'Plumbing Supplies': 'Tools & Hardware',
      'Building Materials': 'Tools & Hardware',
      'Safety Equipment': 'Tools & Hardware',
      'Measuring Tools': 'Tools & Hardware',
      'Tool Storage': 'Tools & Hardware',
    },
    'Pet Supplies': {
      'Dog Supplies': 'Pet Supplies',
      'Cat Supplies': 'Pet Supplies',
      'Bird Supplies': 'Pet Supplies',
      'Fish & Aquarium': 'Pet Supplies',
      'Small Animal Supplies': 'Pet Supplies',
      'Pet Food & Treats': 'Pet Supplies',
      'Pet Care & Health': 'Pet Supplies',
      'Pet Accessories': 'Pet Supplies',
      'Pet Training': 'Pet Supplies',
    },
    'Automotive': {
      'Car Parts & Components': 'Automotive',
      'Car Electronics': 'Automotive',
      'Car Care & Maintenance': 'Automotive',
      'Tires & Wheels': 'Automotive',
      'Interior Accessories': 'Automotive',
      'Exterior Accessories': 'Automotive',
      'Tools & Equipment': 'Automotive',
      'Motorcycle Parts': 'Automotive',
    },
    'Health & Wellness': {
      'Vitamins & Supplements': 'Health & Wellness',
      'Medical Equipment': 'Health & Wellness',
      'First Aid & Safety': 'Health & Wellness',
      'Fitness & Exercise Equipment': 'Health & Wellness',
      'Health Monitoring': 'Health & Wellness',
      'Mobility & Daily Living': 'Health & Wellness',
      'Alternative Medicine': 'Health & Wellness',
      'Personal Care': 'Health & Wellness',
    },
  };

  // ------------------------------------------------------
  // HELPER METHODS FOR BUYER CATEGORIES
  // ------------------------------------------------------

  /// Get product category from buyer selection
  static String? getProductCategoryFromBuyerSelection(
    String buyerCategory,
    String buyerSubcategory,
  ) {
    return kBuyerToProductCategoryMapping[buyerCategory]?[buyerSubcategory];
  }

  /// Get all relevant product categories for a buyer category
  static List<String> getRelevantProductCategories(String buyerCategory) {
    final mapping = kBuyerToProductCategoryMapping[buyerCategory];
    if (mapping != null) {
      return mapping.values.toSet().toList(); // Remove duplicates
    }
    return [];
  }

  /// Filter products by buyer category logic
  static List<Product> filterProductsByBuyerCategory(
    List<Product> products,
    String buyerCategory,
    String? buyerSubcategory,
    String? subSubcategory,
  ) {
    return products.where((product) {
      // First check if product matches the mapped product category
      if (buyerSubcategory != null) {
        final productCategory = getProductCategoryFromBuyerSelection(
          buyerCategory,
          buyerSubcategory,
        );
        if (productCategory != null && product.category != productCategory) {
          return false;
        }
      }

      // Filter by gender for Women/Men categories
      if (buyerCategory == 'Women' || buyerCategory == 'Men') {
        if (!_isProductSuitableForGender(product, buyerCategory)) {
          return false;
        }
      }

      // Filter by subcategory if specified
      if (buyerSubcategory != null) {
        // For Women/Men categories, map buyer subcategory to product subcategory
        if (buyerCategory == 'Women' || buyerCategory == 'Men') {
          final productCategory = getProductCategoryFromBuyerSelection(
            buyerCategory,
            buyerSubcategory,
          );
          if (productCategory != null) {
            // Check if the product's subcategory matches what we expect for this buyer subcategory
            final expectedSubcategories = kSubcategories[productCategory] ?? [];
            if (!expectedSubcategories.contains(product.subcategory)) {
              return false;
            }
          }
        } else {
          // For other categories, direct match
          if (product.subcategory != buyerSubcategory) {
            return false;
          }
        }
      }

      // Filter by sub-subcategory if specified
      if (subSubcategory != null && product.subsubcategory != subSubcategory) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Check if product is suitable for a specific gender
  static bool _isProductSuitableForGender(Product product, String gender) {
    // First check if product has an explicit gender field
    if (product.gender != null) {
      final productGender = product.gender!.toLowerCase();
      final targetGender = gender.toLowerCase();
      return productGender == targetGender ||
          productGender == 'unisex' ||
          productGender == 'both';
    }

    // Fallback to keyword-based logic
    final productName = product.productName.toLowerCase() ?? '';
    final description = product.description.toLowerCase() ?? '';
    final brandModel = product.brandModel?.toLowerCase() ?? '';

    if (gender == 'Women') {
      return productName.contains('women') ||
          productName.contains('female') ||
          productName.contains('ladies') ||
          productName.contains('woman') ||
          description.contains('women') ||
          description.contains('female') ||
          description.contains('ladies') ||
          brandModel.contains('women') ||
          brandModel.contains('ladies');
    } else if (gender == 'Men') {
      return productName.contains('men') ||
          productName.contains('male') ||
          productName.contains('gentlemen') ||
          productName.contains('man') ||
          description.contains('men') ||
          description.contains('male') ||
          description.contains('gentlemen') ||
          brandModel.contains('men') ||
          brandModel.contains('male');
    }

    // If no gender indicators found, include the product (could be unisex)
    return true;
  }

  // ------------------------------------------------------
  // LOCALIZATION HELPERS FOR BUYER CATEGORIES
  // ------------------------------------------------------

  /// Localize buyer category keys
  static String localizeBuyerCategoryKey(String rawKey, AppLocalizations l10n) {
    switch (rawKey) {
      case 'Women':
        return l10n.buyerCategoryWomen ?? 'Women';
      case 'Men':
        return l10n.buyerCategoryMen ?? 'Men';
      case 'Mother & Child':
        return l10n.categoryMotherChild ?? 'Mother & Child';
      case 'Home & Furniture':
        return l10n.categoryHomeFurniture ?? 'Home & Furniture';
      case 'Electronics':
        return l10n.categoryElectronics ?? 'Electronics';
      case 'Books, Stationery & Hobby':
        return l10n.categoryBooksStationeryHobby ?? 'Books, Stationery & Hobby';
      case 'Flowers & Gifts':
        return l10n.categoryFlowersGifts ?? 'Flowers & Gifts';
      case 'Sports & Outdoor':
        return l10n.categorySportsOutdoor ?? 'Sports & Outdoor';
      case 'Tools & Hardware':
        return l10n.categoryToolsHardware ?? 'Tools & Hardware';
      case 'Pet Supplies':
        return l10n.categoryPetSupplies ?? 'Pet Supplies';
      case 'Automotive':
        return l10n.categoryAutomotive ?? 'Automotive';
      case 'Health & Wellness':
        return l10n.categoryHealthWellness ?? 'Health & Wellness';
      default:
        return rawKey;
    }
  }

  /// Localize buyer subcategory keys
  static String localizeBuyerSubcategoryKey(
    String parentCategory,
    String rawKey,
    AppLocalizations l10n,
  ) {
    switch (parentCategory) {
      case 'Women':
      case 'Men':
        switch (rawKey) {
          case 'Fashion':
            return l10n.buyerSubcategoryFashion ?? 'Fashion';
          case 'Shoes':
            return l10n.buyerSubcategoryShoes ?? 'Shoes';
          case 'Accessories':
            return l10n.buyerSubcategoryAccessories ?? 'Accessories';
          case 'Bags':
            return l10n.buyerSubcategoryBags ?? 'Bags';
          case 'Self Care':
            return l10n.buyerSubcategorySelfCare ?? 'Self Care';
        }
        break;
      default:
        // For other categories, use the existing localization
        return localizeSubcategoryKey(parentCategory, rawKey, l10n);
    }
    return rawKey;
  }

  /// Localize buyer sub-subcategory keys
  static String localizeBuyerSubSubcategoryKey(
    String parentCategory,
    String parentSubcategory,
    String rawKey,
    AppLocalizations l10n,
  ) {
    switch (parentCategory) {
      case 'Women':
      case 'Men':
        switch (parentSubcategory) {
          case 'Fashion':
            // For Fashion, rawKey is actually a subcategory like "Dresses", "Tops & Shirts", etc.
            return localizeSubcategoryKey('Clothing & Fashion', rawKey, l10n);
          case 'Shoes':
            // For Shoes, rawKey is actually a subcategory like "Sneakers & Athletic", "Casual Shoes", etc.
            return localizeSubcategoryKey('Footwear', rawKey, l10n);
          case 'Accessories':
            // For Accessories, rawKey is actually a subcategory like "Jewelry", "Watches", etc.
            return localizeSubcategoryKey('Accessories', rawKey, l10n);
          case 'Bags':
            // For Bags, rawKey is actually a subcategory like "Handbags", "Backpacks", etc.
            return localizeSubcategoryKey('Bags & Luggage', rawKey, l10n);
          case 'Self Care':
            // For Self Care, rawKey is actually a subcategory like "Skincare", "Makeup", etc.
            return localizeSubcategoryKey(
                'Beauty & Personal Care', rawKey, l10n);
          default:
            return rawKey;
        }
      default:
        // For other categories, use the existing localization
        return localizeSubSubcategoryKey(
            parentCategory, parentSubcategory, rawKey, l10n);
    }
  }

  // ------------------------------------------------------
  // UTILITY METHODS
  // ------------------------------------------------------

  /// Check if we should use buyer categories or product categories
  static bool shouldUseBuyerCategories() {
    // You can add logic here to determine when to use buyer vs product categories
    // For example, check user role, app settings, etc.
    return true; // Default to buyer categories for customer-facing UI
  }

  /// Get appropriate categories based on context
  static List<Map<String, String>> getCategories(
      {bool forceBuyerCategories = false}) {
    if (forceBuyerCategories || shouldUseBuyerCategories()) {
      return kBuyerCategories;
    }
    return kCategories;
  }

  /// Get appropriate subcategories based on context
  static List<String> getSubcategories(String category,
      {bool forceBuyerCategories = false}) {
    if (forceBuyerCategories || shouldUseBuyerCategories()) {
      return kBuyerSubcategories[category] ?? [];
    }
    return kSubcategories[category] ?? [];
  }

  /// Get appropriate sub-subcategories based on context
  static List<String> getSubSubcategories(String category, String subcategory,
      {bool forceBuyerCategories = false}) {
    if (forceBuyerCategories || shouldUseBuyerCategories()) {
      return kBuyerSubSubcategories[category]?[subcategory] ?? [];
    }
    return kSubSubcategories[category]?[subcategory] ?? [];
  }

  /// Convert buyer category selection to product category for backend queries
  static Map<String, String?> getBuyerToProductMapping(
    String buyerCategory,
    String? buyerSubcategory,
    String? buyerSubSubcategory,
  ) {
    final productCategory = buyerSubcategory != null
        ? getProductCategoryFromBuyerSelection(buyerCategory, buyerSubcategory)
        : null;

    String? productSubcategory;

    // For Women/Men categories, the "subSubcategory" is actually the product subcategory
    if ((buyerCategory == 'Women' || buyerCategory == 'Men')) {
      productSubcategory =
          buyerSubSubcategory; // "Dresses", "Tops & Shirts", etc.
    } else {
      productSubcategory = buyerSubcategory;
    }

    return {
      'category': productCategory,
      'subcategory': productSubcategory,
      'subSubcategory': null, // Don't filter by subsubcategory - show all
    };
  }
}
