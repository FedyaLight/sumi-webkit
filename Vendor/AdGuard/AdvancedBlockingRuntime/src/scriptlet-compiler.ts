import { scriptlets as ScriptletsAPI } from '@adguard/scriptlets';

declare global {
  // eslint-disable-next-line no-var
  var sumiCompileScriptlet: (name: string, args: string[]) => string;
}

globalThis.sumiCompileScriptlet = (name: string, args: string[]): string => ScriptletsAPI.invoke({
  engine: 'safari-extension',
  name,
  args,
  version: '4.3.0',
  verbose: false,
});
