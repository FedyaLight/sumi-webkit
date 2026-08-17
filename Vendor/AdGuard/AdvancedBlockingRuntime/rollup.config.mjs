import commonjs from '@rollup/plugin-commonjs';
import json from '@rollup/plugin-json';
import resolve from '@rollup/plugin-node-resolve';
import typescript from '@rollup/plugin-typescript';

const plugins = () => [
  json({ preferConst: true }),
  commonjs({ sourceMap: false }),
  resolve({ preferBuiltins: false }),
  typescript({ compilerOptions: { declaration: false } }),
];

export default [
  {
    input: 'src/page-runtime.ts',
    output: {
      file: 'dist/sumi-advanced-blocking.js',
      format: 'iife',
      banner: '/* SafariConverterLib 4.3.0 page runtime; GPL-3.0; adapted for Sumi. */',
    },
    plugins: plugins(),
  },
  {
    input: 'src/scriptlet-compiler.ts',
    output: {
      file: 'dist/sumi-scriptlet-compiler.js',
      format: 'iife',
      banner: '/* AdGuard Scriptlets 2.3.1 compiler; GPL-3.0; adapted for Sumi. */',
    },
    plugins: plugins(),
  },
];
