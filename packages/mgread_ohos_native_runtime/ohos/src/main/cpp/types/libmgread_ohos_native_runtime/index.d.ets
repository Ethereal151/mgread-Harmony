declare const nativeRuntime: {
  version(): string;
  create(configJson: string): number;
  start(): number;
  invoke(requestJson: string): Promise<string>;
  cancel(requestId: string): number;
  stop(): number;
  restart(): number;
  dispose(): void;
};

export default nativeRuntime;
