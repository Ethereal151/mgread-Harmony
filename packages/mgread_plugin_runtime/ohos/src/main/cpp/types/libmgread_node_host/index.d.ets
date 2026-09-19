declare const mgreadNodeHost: {
  initialize(runtimeRoot: string, dataRoot: string, pluginImportInboxRoot: string): void;
  invoke(requestId: string, method: string, paramsJson: string, deadlineUnixMs: number): string;
  invokeAsync(requestId: string, method: string, paramsJson: string, deadlineUnixMs: number): Promise<string>;
  cancelInvocation(requestId: string): boolean;
  runtimePaths(): string;
  materializeTransfer(token: string, destination: string): string;
  restart(): string;
  setProgressCallback(callback: (payload: string) => void): void;
  setBrowserSessionCallback(callback: (requestId: string, payload: string) => void): void;
  resolveBrowserSession(requestId: string, response: string): void;
  clearBrowserSessionCallback(): void;
  dispose(): void;
  runtimeVersion(): string;
  nativeNodeHostAvailable(): boolean;
};

export default mgreadNodeHost;
