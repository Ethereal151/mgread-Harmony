import fs from 'fs';
import path from 'path'
import { appTasks, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { hvigor, HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { flutterHvigorPlugin } from 'flutter-hvigor-plugin';
import { bridgeCrossDrivePlugins } from './flutter_ohos_plugin_bridge';

bridgeCrossDrivePlugins();

type FlutterNativeArchitecture = 'arm64_v8a' | 'x86_64';

function normalizeFlutterHvigorContexts(rootNode: HvigorNode): void {
    const targetPlatform = hvigor.getParameter().getExtParam('TARGET_PLATFORM')
        ?.split(',')
        .map(platform => platform.trim())
        .find(platform => platform === 'ohos-arm64' || platform === 'ohos-x64') ?? 'ohos-arm64';
    const buildMode = hvigor.getParameter().getExtParam('buildMode') ?? 'debug';
    const nativePackage = targetPlatform === 'ohos-x64'
        ? 'flutter_native_x86_64'
        : 'flutter_native_arm64_v8a';
    const otherNativePackage = nativePackage === 'flutter_native_x86_64'
        ? 'flutter_native_arm64_v8a'
        : 'flutter_native_x86_64';
    const engineDirectory = `ohos-${targetPlatform === 'ohos-x64' ? 'x64' : 'arm64'}${
        buildMode === 'debug' ? '' : `-${buildMode}`
    }`;
    const rewriteFlutterPath = (value: unknown): unknown => {
        if (typeof value !== 'string') {
            return value;
        }
        return value
            .replace(/ohos-(?:arm64|x64)(?:-(?:profile|release))?/g, engineDirectory)
            .replace(/flutter_embedding_(?:debug|profile|release)\.har/g, `flutter_embedding_${buildMode}.har`)
            .replace(/(?:arm64_v8a|x86_64)_(?:debug|profile|release)\.har/g, `${nativePackage.replace('flutter_native_', '')}_${buildMode}.har`);
    };

    rootNode.afterNodeEvaluate(() => {
        const appContext = rootNode.getContext(OhosPluginId.OHOS_APP_PLUGIN) as {
            getOverrides(): Record<string, unknown> | undefined;
            setOverrides(value: Record<string, unknown>): void;
        };
        const overrides = appContext.getOverrides() ?? {};
        const nativeOverride = overrides[nativePackage] ?? overrides[otherNativePackage];
        delete overrides[otherNativePackage];
        overrides['@ohos/flutter_ohos'] = rewriteFlutterPath(overrides['@ohos/flutter_ohos']);
        if (nativeOverride !== undefined) {
            overrides[nativePackage] = rewriteFlutterPath(nativeOverride);
        }
        appContext.setOverrides(overrides);
    });

    rootNode.subNodes(subNode => {
        subNode.afterNodeEvaluate(node => {
            for (const contextId of [OhosPluginId.OHOS_HAP_PLUGIN, OhosPluginId.OHOS_HAR_PLUGIN]) {
                const context = node.getContext(contextId) as {
                    getDependenciesOpt(): Record<string, unknown>;
                    setDependenciesOpt(value: Record<string, unknown>): void;
                } | undefined;
                if (!context) {
                    continue;
                }
                const dependencies = context.getDependenciesOpt();
                delete dependencies[otherNativePackage];
                const appContext = rootNode.getContext(OhosPluginId.OHOS_APP_PLUGIN) as {
                    getOverrides(): Record<string, unknown> | undefined;
                };
                const overrides = appContext.getOverrides() ?? {};
                const embeddingPath = rewriteFlutterPath(overrides['@ohos/flutter_ohos']);
                const nativePath = rewriteFlutterPath(overrides[nativePackage]);
                if (typeof embeddingPath !== 'string' || typeof nativePath !== 'string') {
                    throw new Error('Flutter OHOS local HAR overrides were not resolved before module dependency evaluation.');
                }
                dependencies['@ohos/flutter_ohos'] = embeddingPath;
                dependencies[nativePackage] = nativePath;
                context.setDependenciesOpt(dependencies);
            }
        });
    });
}

function selectedFlutterNativeArchitecture(): FlutterNativeArchitecture {
    const targetPlatforms = hvigor.getParameter().getExtParam('TARGET_PLATFORM')
        ?.split(',')
        .map(platform => platform.trim());
    return targetPlatforms?.length === 1 && targetPlatforms[0] === 'ohos-x64'
        ? 'x86_64'
        : 'arm64_v8a';
}

function pruneNonOhosFlutterOutputs(
    nodePath: string,
    selectedArchitecture: FlutterNativeArchitecture,
): void {
    const rawfilePath = path.join(nodePath, 'src', 'main', 'resources', 'rawfile');
    const runtimeRoot = path.join(rawfilePath, 'flutter_assets', 'packages', 'mgread_plugin_runtime', 'assets', 'runtime');
    for (const platform of ['android', 'windows-x64', 'macos-arm64']) {
        const platformPath = path.join(runtimeRoot, platform);
        if (fs.existsSync(platformPath)) {
            fs.rmSync(platformPath, { recursive: true, force: true });
        }
    }

    // Keep the other ABI's native inputs on disk. build-profile.json5 excludes
    // the unselected ABI from this HAP; deleting it here destroys the inputs
    // needed by the next architecture build.
    const unselectedNativeLibDirectory = selectedArchitecture === 'x86_64'
        ? 'arm64-v8a'
        : 'x86_64';
    const unselectedLibsPath = path.join(nodePath, 'libs', unselectedNativeLibDirectory);
    if (fs.existsSync(unselectedLibsPath)) {
        console.log(`Preserving unselected OHOS native inputs: ${unselectedLibsPath}`);
    }

}

const singleArchitectureFlutterPlugin: HvigorPlugin = {
    pluginId: 'mgread-single-architecture-flutter',
    apply(rootNode: HvigorNode) {
        const selectedArchitecture = selectedFlutterNativeArchitecture();
        rootNode.subNodes(subNode => {
            subNode.afterNodeEvaluate(node => {
                if (subNode.getNodeName() === 'entry') {
                    const flutterTask = node.getTaskByName('default@FlutterTask');
                    flutterTask?.afterRun(() => pruneNonOhosFlutterOutputs(
                        node.getNodePath(),
                        selectedArchitecture,
                    ));
                }
            });
        });
    },
};

const normalizeFlutterPackageMetadataPlugin: HvigorPlugin = {
    pluginId: 'mgread-normalize-flutter-package-metadata',
    apply(rootNode: HvigorNode) {
        normalizeFlutterHvigorContexts(rootNode);
    },
};

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[
        flutterHvigorPlugin(path.dirname(__dirname)),
        normalizeFlutterPackageMetadataPlugin,
        singleArchitectureFlutterPlugin,
    ]         /* Custom plugin to extend the functionality of Hvigor. */
}
