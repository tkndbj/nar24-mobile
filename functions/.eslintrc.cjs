// functions/.eslintrc.cjs

module.exports = {
  root: true,
  env: {
    node: true,
    es2020: true,
    jest: true,
  },
  extends: [
    'eslint:recommended',
    'google',
  ],
  parserOptions: {
    ecmaVersion: 2020,
    sourceType: 'module',
  },
  rules: {
    'no-console': 'off',
    'indent': 'off',
    'comma-dangle': 'off',
    'no-unused-expressions': 'off',
    'require-jsdoc': 'off',
    'max-len': ['error', {'code': 400}],
    'linebreak-style': 'off',
    'no-trailing-spaces': 'off',
    'object-curly-spacing': 'off',
    'no-multi-spaces': 'off',
    'brace-style': 'off',
    'object-curly-newline': 'off',
    'space-in-parens': 'off',
  },
};
