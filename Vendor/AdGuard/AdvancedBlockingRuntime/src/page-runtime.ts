import { ExtendedCss } from '@adguard/extended-css';

type Configuration = {
  extendedCss: string[];
};

declare const configuration: Configuration;

const toCssRules = (rules: string[]): string[] => rules
  .map((rule) => rule.trim())
  .filter(Boolean)
  .map((rule) => (rule.endsWith('}') ? rule : `${rule} {display:none!important;}`));

const applyConfiguration = (configuration: Configuration) => {
  if (configuration.extendedCss.length) {
    try {
      new ExtendedCss({ cssRules: toCssRules(configuration.extendedCss) }).apply();
    } catch {
      // One invalid ExtendedCSS rule must not affect the page lifecycle.
    }
  }
};

applyConfiguration(configuration);
