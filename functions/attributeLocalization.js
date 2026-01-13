// functions/utils/attributeLocalization.js

const localizeAttributeKey = (key, lang = 'en') => {
  const translations = {
    en: {
      selectedColor: 'Color',
      selectedSize: 'Size',
      gender: 'Gender',
      clothingSizes: 'Clothing Size',
      clothingFit: 'Fit',
      clothingType: 'Type',
      footwearSizes: 'Shoe Size',
      pantSizes: 'Pant Size',
      jewelryType: 'Jewelry Type',
      jewelryMaterials: 'Material',
      computerComponent: 'Component',
      consoleBrand: 'Console Brand',
      consoleVariant: 'Console Model',
      kitchenAppliance: 'Appliance',
      whiteGood: 'Appliance Type',
    },
    tr: {
      selectedColor: 'Renk',
      selectedSize: 'Beden',
      gender: 'Cinsiyet',
      clothingSizes: 'Giysi Bedeni',
      clothingFit: 'Kalıp',
      clothingType: 'Tür',
      footwearSizes: 'Ayakkabı Numarası',
      pantSizes: 'Pantolon Bedeni',
      jewelryType: 'Takı Türü',
      jewelryMaterials: 'Malzeme',
      computerComponent: 'Bileşen',
      consoleBrand: 'Konsol Markası',
      consoleVariant: 'Konsol Modeli',
      kitchenAppliance: 'Mutfak Aleti',
      whiteGood: 'Beyaz Eşya',
    },
    ru: {
      selectedColor: 'Цвет',
      selectedSize: 'Размер',
      gender: 'Пол',
      clothingSizes: 'Размер одежды',
      clothingFit: 'Посадка',
      clothingType: 'Тип',
      footwearSizes: 'Размер обуви',
      pantSizes: 'Размер брюк',
      jewelryType: 'Тип украшения',
      jewelryMaterials: 'Материал',
      computerComponent: 'Компонент',
      consoleBrand: 'Бренд консоли',
      consoleVariant: 'Модель консоли',
      kitchenAppliance: 'Кухонный прибор',
      whiteGood: 'Бытовая техника',
    },
  };

  return translations[lang]?.[key] || formatAttributeKey(key);
};

const localizeAttributeValue = (key, value, lang = 'en') => {
  const stringValue = value.toString();

  switch (key) {
  case 'selectedColor':
    return localizeColor(stringValue, lang);
  case 'gender':
    return localizeGender(stringValue, lang);
  case 'clothingSizes':
    return localizeClothingSize(stringValue, lang);
  case 'clothingFit':
    return localizeClothingFit(stringValue, lang);
  case 'clothingType':
    return localizeClothingType(stringValue, lang);
  case 'jewelryType':
    return localizeJewelryType(stringValue, lang);
  case 'jewelryMaterials':
    return localizeJewelryMaterial(stringValue, lang);
  case 'computerComponent':
    return localizeComputerComponent(stringValue, lang);
  case 'consoleBrand':
    return localizeConsoleBrand(stringValue, lang);
  case 'consoleVariant':
    return localizeConsoleVariant(stringValue, lang);
  case 'kitchenAppliance':
    return localizeKitchenAppliance(stringValue, lang);
  case 'whiteGood':
    return localizeWhiteGood(stringValue, lang);
  default:
    return stringValue;
  }
};

const localizeColor = (color, lang = 'en') => {
  const colors = {
    en: {
      'Blue': 'Blue',
      'Orange': 'Orange',
      'Yellow': 'Yellow',
      'Black': 'Black',
      'Brown': 'Brown',
      'Dark Blue': 'Dark Blue',
      'Gray': 'Gray',
      'Pink': 'Pink',
      'Red': 'Red',
      'White': 'White',
      'Green': 'Green',
      'Purple': 'Purple',
      'Teal': 'Teal',
      'Lime': 'Lime',
      'Cyan': 'Cyan',
      'Magenta': 'Magenta',
      'Indigo': 'Indigo',
      'Amber': 'Amber',
      'Deep Orange': 'Deep Orange',
      'Light Blue': 'Light Blue',
      'Deep Purple': 'Deep Purple',
      'Light Green': 'Light Green',
      'Dark Gray': 'Dark Gray',
      'Beige': 'Beige',
      'Turquoise': 'Turquoise',
      'Violet': 'Violet',
      'Olive': 'Olive',
      'Maroon': 'Maroon',
      'Navy': 'Navy',
      'Silver': 'Silver',
    },
    tr: {
      'Blue': 'Mavi',
      'Orange': 'Turuncu',
      'Yellow': 'Sarı',
      'Black': 'Siyah',
      'Brown': 'Kahverengi',
      'Dark Blue': 'Koyu Mavi',
      'Gray': 'Gri',
      'Pink': 'Pembe',
      'Red': 'Kırmızı',
      'White': 'Beyaz',
      'Green': 'Yeşil',
      'Purple': 'Mor',
      'Teal': 'Camgöbeği',
      'Lime': 'Limon Yeşili',
      'Cyan': 'Cam Göbeği',
      'Magenta': 'Eflatun',
      'Indigo': 'Çivit',
      'Amber': 'Kehribar',
      'Deep Orange': 'Koyu Turuncu',
      'Light Blue': 'Açık Mavi',
      'Deep Purple': 'Koyu Mor',
      'Light Green': 'Açık Yeşil',
      'Dark Gray': 'Koyu Gri',
      'Beige': 'Bej',
      'Turquoise': 'Turkuaz',
      'Violet': 'Menekşe',
      'Olive': 'Zeytin',
      'Maroon': 'Bordo',
      'Navy': 'Lacivert',
      'Silver': 'Gümüş',
    },
    ru: {
      'Blue': 'Синий',
      'Orange': 'Оранжевый',
      'Yellow': 'Желтый',
      'Black': 'Черный',
      'Brown': 'Коричневый',
      'Dark Blue': 'Темно-синий',
      'Gray': 'Серый',
      'Pink': 'Розовый',
      'Red': 'Красный',
      'White': 'Белый',
      'Green': 'Зеленый',
      'Purple': 'Фиолетовый',
      'Teal': 'Бирюзовый',
      'Lime': 'Лаймовый',
      'Cyan': 'Голубой',
      'Magenta': 'Пурпурный',
      'Indigo': 'Индиго',
      'Amber': 'Янтарный',
      'Deep Orange': 'Темно-оранжевый',
      'Light Blue': 'Светло-синий',
      'Deep Purple': 'Темно-фиолетовый',
      'Light Green': 'Светло-зеленый',
      'Dark Gray': 'Темно-серый',
      'Beige': 'Бежевый',
      'Turquoise': 'Бирюзовый',
      'Violet': 'Фиалковый',
      'Olive': 'Оливковый',
      'Maroon': 'Бордовый',
      'Navy': 'Темно-синий',
      'Silver': 'Серебряный',
    },
  };

  return colors[lang]?.[color] || color;
};

const localizeGender = (gender, lang = 'en') => {
  const genders = {
    en: {
      'Women': 'Women',
      'Men': 'Men',
      'Unisex': 'Unisex',
    },
    tr: {
      'Women': 'Kadın',
      'Men': 'Erkek',
      'Unisex': 'Unisex',
    },
    ru: {
      'Women': 'Женский',
      'Men': 'Мужской',
      'Unisex': 'Унисекс',
    },
  };

  return genders[lang]?.[gender] || gender;
};

const localizeClothingSize = (size, lang = 'en') => {
  // Standard sizes stay the same across languages
  return size;
};

const localizeClothingFit = (fit, lang = 'en') => {
  const fits = {
    en: {
      'Regular': 'Regular',
      'Slim': 'Slim',
      'Loose': 'Loose',
      'Oversized': 'Oversized',
      'Skinny': 'Skinny',
      'Relaxed': 'Relaxed',
    },
    tr: {
      'Regular': 'Normal',
      'Slim': 'Dar',
      'Loose': 'Bol',
      'Oversized': 'Oversize',
      'Skinny': 'Skinny',
      'Relaxed': 'Rahat',
    },
    ru: {
      'Regular': 'Обычный',
      'Slim': 'Приталенный',
      'Loose': 'Свободный',
      'Oversized': 'Оверсайз',
      'Skinny': 'Облегающий',
      'Relaxed': 'Расслабленный',
    },
  };

  return fits[lang]?.[fit] || fit;
};

const localizeClothingType = (type, lang = 'en') => {
  const types = {
    en: {
      'Shirt': 'Shirt',
      'T-Shirt': 'T-Shirt',
      'Pants': 'Pants',
      'Jeans': 'Jeans',
      'Dress': 'Dress',
      'Skirt': 'Skirt',
      'Jacket': 'Jacket',
      'Coat': 'Coat',
      'Sweater': 'Sweater',
      'Hoodie': 'Hoodie',
    },
    tr: {
      'Shirt': 'Gömlek',
      'T-Shirt': 'Tişört',
      'Pants': 'Pantolon',
      'Jeans': 'Kot',
      'Dress': 'Elbise',
      'Skirt': 'Etek',
      'Jacket': 'Ceket',
      'Coat': 'Kaban',
      'Sweater': 'Kazak',
      'Hoodie': 'Kapüşonlu',
    },
    ru: {
      'Shirt': 'Рубашка',
      'T-Shirt': 'Футболка',
      'Pants': 'Брюки',
      'Jeans': 'Джинсы',
      'Dress': 'Платье',
      'Skirt': 'Юбка',
      'Jacket': 'Куртка',
      'Coat': 'Пальто',
      'Sweater': 'Свитер',
      'Hoodie': 'Худи',
    },
  };

  return types[lang]?.[type] || type;
};

const localizeJewelryType = (type, lang = 'en') => {
  const types = {
    en: {
      'Necklace': 'Necklace',
      'Earring': 'Earring',
      'Piercing': 'Piercing',
      'Ring': 'Ring',
      'Bracelet': 'Bracelet',
      'Anklet': 'Anklet',
      'NoseRing': 'Nose Ring',
      'Set': 'Set',
    },
    tr: {
      'Necklace': 'Kolye',
      'Earring': 'Küpe',
      'Piercing': 'Piercing',
      'Ring': 'Yüzük',
      'Bracelet': 'Bileklik',
      'Anklet': 'Halhal',
      'NoseRing': 'Burun Halkası',
      'Set': 'Set',
    },
    ru: {
      'Necklace': 'Ожерелье',
      'Earring': 'Серьги',
      'Piercing': 'Пирсинг',
      'Ring': 'Кольцо',
      'Bracelet': 'Браслет',
      'Anklet': 'Браслет на ногу',
      'NoseRing': 'Кольцо для носа',
      'Set': 'Набор',
    },
  };

  return types[lang]?.[type] || type;
};

const localizeJewelryMaterial = (material, lang = 'en') => {
  const materials = {
    en: {
      'Iron': 'Iron',
      'Steel': 'Steel',
      'Gold': 'Gold',
      'Silver': 'Silver',
      'Diamond': 'Diamond',
      'Copper': 'Copper',
    },
    tr: {
      'Iron': 'Demir',
      'Steel': 'Çelik',
      'Gold': 'Altın',
      'Silver': 'Gümüş',
      'Diamond': 'Elmas',
      'Copper': 'Bakır',
    },
    ru: {
      'Iron': 'Железо',
      'Steel': 'Сталь',
      'Gold': 'Золото',
      'Silver': 'Серебро',
      'Diamond': 'Алмаз',
      'Copper': 'Медь',
    },
  };

  return materials[lang]?.[material] || material;
};

const localizeComputerComponent = (component, lang = 'en') => {
  const components = {
    en: {
      'CPU': 'CPU',
      'GPU': 'GPU',
      'RAM': 'RAM',
      'Motherboard': 'Motherboard',
      'SSD': 'SSD',
      'HDD': 'HDD',
      'PowerSupply': 'Power Supply',
      'CoolingSystem': 'Cooling System',
      'Case': 'Case',
      'OpticalDrive': 'Optical Drive',
      'NetworkCard': 'Network Card',
      'SoundCard': 'Sound Card',
      'Webcam': 'Webcam',
      'Headset': 'Headset',
    },
    tr: {
      'CPU': 'İşlemci',
      'GPU': 'Ekran Kartı',
      'RAM': 'RAM',
      'Motherboard': 'Anakart',
      'SSD': 'SSD',
      'HDD': 'HDD',
      'PowerSupply': 'Güç Kaynağı',
      'CoolingSystem': 'Soğutma Sistemi',
      'Case': 'Kasa',
      'OpticalDrive': 'Optik Sürücü',
      'NetworkCard': 'Ağ Kartı',
      'SoundCard': 'Ses Kartı',
      'Webcam': 'Web Kamerası',
      'Headset': 'Kulaklık',
    },
    ru: {
      'CPU': 'Процессор',
      'GPU': 'Видеокарта',
      'RAM': 'ОЗУ',
      'Motherboard': 'Материнская плата',
      'SSD': 'SSD',
      'HDD': 'HDD',
      'PowerSupply': 'Блок питания',
      'CoolingSystem': 'Система охлаждения',
      'Case': 'Корпус',
      'OpticalDrive': 'Оптический привод',
      'NetworkCard': 'Сетевая карта',
      'SoundCard': 'Звуковая карта',
      'Webcam': 'Веб-камера',
      'Headset': 'Гарнитура',
    },
  };

  return components[lang]?.[component] || component;
};

const localizeConsoleBrand = (brand, lang = 'en') => {
  const brands = {
    en: {
      'PlayStation': 'PlayStation',
      'Xbox': 'Xbox',
      'Nintendo': 'Nintendo',
      'PC': 'PC',
      'Mobile': 'Mobile',
      'Retro': 'Retro',
    },
    tr: {
      'PlayStation': 'PlayStation',
      'Xbox': 'Xbox',
      'Nintendo': 'Nintendo',
      'PC': 'PC',
      'Mobile': 'Mobil',
      'Retro': 'Retro',
    },
    ru: {
      'PlayStation': 'PlayStation',
      'Xbox': 'Xbox',
      'Nintendo': 'Nintendo',
      'PC': 'ПК',
      'Mobile': 'Мобильный',
      'Retro': 'Ретро',
    },
  };

  return brands[lang]?.[brand] || brand;
};

const localizeConsoleVariant = (variant, lang = 'en') => {
  // Console variants typically remain in their original naming
  // across languages, but you can add translations if needed
  return variant;
};

const localizeKitchenAppliance = (appliance, lang = 'en') => {
  const appliances = {
    en: {
      'Microwave': 'Microwave',
      'CoffeeMachine': 'Coffee Machine',
      'Blender': 'Blender',
      'FoodProcessor': 'Food Processor',
      'Mixer': 'Mixer',
      'Toaster': 'Toaster',
      'Kettle': 'Kettle',
      'RiceCooker': 'Rice Cooker',
      'SlowCooker': 'Slow Cooker',
      'PressureCooker': 'Pressure Cooker',
      'AirFryer': 'Air Fryer',
      'Juicer': 'Juicer',
      'Grinder': 'Grinder',
      'Oven': 'Oven',
    },
    tr: {
      'Microwave': 'Mikrodalga',
      'CoffeeMachine': 'Kahve Makinesi',
      'Blender': 'Blender',
      'FoodProcessor': 'Mutfak Robotu',
      'Mixer': 'Mikser',
      'Toaster': 'Tost Makinesi',
      'Kettle': 'Su Isıtıcı',
      'RiceCooker': 'Pirinç Pişirici',
      'SlowCooker': 'Yavaş Pişirici',
      'PressureCooker': 'Düdüklü Tencere',
      'AirFryer': 'Airfryer',
      'Juicer': 'Meyve Sıkacağı',
      'Grinder': 'Öğütücü',
      'Oven': 'Fırın',
    },
    ru: {
      'Microwave': 'Микроволновка',
      'CoffeeMachine': 'Кофемашина',
      'Blender': 'Блендер',
      'FoodProcessor': 'Кухонный комбайн',
      'Mixer': 'Миксер',
      'Toaster': 'Тостер',
      'Kettle': 'Чайник',
      'RiceCooker': 'Рисоварка',
      'SlowCooker': 'Медленноварка',
      'PressureCooker': 'Скороварка',
      'AirFryer': 'Аэрофритюрница',
      'Juicer': 'Соковыжималка',
      'Grinder': 'Измельчитель',
      'Oven': 'Духовка',
    },
  };

  return appliances[lang]?.[appliance] || appliance;
};

const localizeWhiteGood = (whiteGood, lang = 'en') => {
  const goods = {
    en: {
      'Refrigerator': 'Refrigerator',
      'WashingMachine': 'Washing Machine',
      'Dishwasher': 'Dishwasher',
      'Dryer': 'Dryer',
      'Freezer': 'Freezer',
    },
    tr: {
      'Refrigerator': 'Buzdolabı',
      'WashingMachine': 'Çamaşır Makinesi',
      'Dishwasher': 'Bulaşık Makinesi',
      'Dryer': 'Kurutma Makinesi',
      'Freezer': 'Derin Dondurucu',
    },
    ru: {
      'Refrigerator': 'Холодильник',
      'WashingMachine': 'Стиральная машина',
      'Dishwasher': 'Посудомоечная машина',
      'Dryer': 'Сушилка',
      'Freezer': 'Морозильник',
    },
  };

  return goods[lang]?.[whiteGood] || whiteGood;
};

const formatAttributeKey = (key) => {
  // Remove 'selected' prefix if present
  const cleanKey = key.replace(/^selected/, '');
  // Convert camelCase to Title Case
  return cleanKey
    .replace(/([A-Z])/g, ' $1')
    .trim()
    .split(' ')
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(' ');
};

export {
  localizeAttributeKey,
  localizeAttributeValue,
  formatAttributeKey,
};
