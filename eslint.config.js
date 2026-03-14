const lwcRecommended = require('@salesforce/eslint-config-lwc/recommended');

module.exports = [
  ...lwcRecommended,
  {
    ignores: ['**/__tests__/**'],
  },
];
