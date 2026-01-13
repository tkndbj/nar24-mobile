// functions/i18n.cjs

const en = require('./l10n/app_en.json');
const tr = require('./l10n/app_tr.json');
const ru = require('./l10n/app_ru.json');

const ARB = {en, tr, ru};

/**
 * @param {'category'|'subcategory'|'subSubcategory'|'jewelryType'|'jewelryMaterial'} prefix
 * @param {string} rawKey
 * @param {'en'|'tr'|'ru'} locale
 * @return {string}
 */
function localize(prefix, rawKey, locale) {
  // Add safety checks
  if (!rawKey || !locale || !prefix) {
    console.warn(`Localize: Missing parameters - prefix="${prefix}", rawKey="${rawKey}", locale="${locale}"`);
    return rawKey || '';
  }

  if (!ARB[locale]) {
    console.error(`Localize: Locale "${locale}" not found in ARB`);
    return rawKey;
  }

  const id = prefix +
    rawKey
      .replace(/[^A-Za-z0-9]+/g, ' ')
      .split(' ')
      .filter((w) => w.length > 0) // Remove empty strings!
      .map((w, i) => i === 0 ? w : w[0].toUpperCase() + w.slice(1))
      .join('');

  console.log(`Localize: prefix="${prefix}", rawKey="${rawKey}", locale="${locale}", generated id="${id}"`);

  const result = ARB[locale][id];
  if (result) {
    console.log(`✅ Translation found: "${id}" -> "${result}"`);
    return result;
  } else {
    console.warn(`❌ Translation NOT found for key "${id}" in locale "${locale}"`);
    return rawKey;
  }
}

module.exports = {localize};
