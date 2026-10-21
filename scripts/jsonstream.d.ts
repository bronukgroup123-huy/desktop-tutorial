declare module 'JSONStream' {
  import { Transform } from 'node:stream';

  interface JSONStreamOptions {
    separator?: string;
  }

  function parse(path: string, map?: (data: unknown, key: number) => unknown): Transform;
  function stringify(open?: string, sep?: string, close?: string): Transform;
  function stringifyObject(open?: string, sep?: string, close?: string): Transform;

  namespace JSONStream {
    export { parse, stringify, stringifyObject };
  }

  export = JSONStream;
}