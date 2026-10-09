declare const nativeRuntime: {
  version(): string;
  create(configJson: string): number;
  start(): number;
  invoke(requestJson: string): Promise<string>;
  lastError(): string;
  cancel(requestId: string): number;
  stop(): number;
  restart(): number;
  hostStart(root: string, token: string, nativeLibraryDir: string, testMode: boolean): string;
  hostStop(): number;
  dispose(): void;
};

export default nativeRuntime;
