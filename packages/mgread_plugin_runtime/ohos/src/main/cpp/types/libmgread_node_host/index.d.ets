declare const mgreadNodeHost: {
  initialize(runtimeRoot: string, dataRoot: string, pluginImportInboxRoot: string): void;
  invoke(requestId: string, method: string, paramsJson: string, deadlineUnixMs: number): string;
  cancelInvocation(requestId: string): boolean;
  runtimePaths(): string;
  materializeTransfer(token: string, destination: string): string;
  restart(): string;
  setProgressCallback(callback: (payload: string) => void): void;
  dispose(): void;
  runtimeVersion(): string;
};

export default mgreadNodeHost;
