import fs from 'fs';
import path from 'path'
import { appTasks, OhosAppContext, OhosHarContext, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { hvigor, HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { flutterHvigorPlugin } from 'flutter-hvigor-plugin';
import { bridgeCrossDrivePlugins } from './flutter_ohos_plugin_bridge';

bridgeCrossDrivePlugins();

type FlutterNativeArchitecture = 'arm64_v8a' | 'x86_64';

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

    const unselectedNativeLibDirectory = selectedArchitecture === 'x86_64'
        ? 'arm64-v8a'
        : 'x86_64';
    const unselectedLibsPath = path.join(nodePath, 'libs', unselectedNativeLibDirectory);
    if (fs.existsSync(unselectedLibsPath)) {
        fs.rmSync(unselectedLibsPath, { recursive: true, force: true });
    }

}

const singleArchitectureFlutterPlugin: HvigorPlugin = {
    pluginId: 'mgread-single-architecture-flutter',
    apply(rootNode: HvigorNode) {
        const selectedArchitecture = selectedFlutterNativeArchitecture();
        const unselectedArchitecture: FlutterNativeArchitecture = selectedArchitecture === 'x86_64'
            ? 'arm64_v8a'
            : 'x86_64';
        rootNode.afterNodeEvaluate(node => {
            const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
            const overrides = appContext.getOverrides() ?? {};
            delete overrides[`flutter_native_${unselectedArchitecture}`];
            appContext.setOverrides(overrides);
        });
        rootNode.subNodes(subNode => {
            subNode.afterNodeEvaluate(node => {
                const hapContext = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext | undefined;
                const harContext = node.getContext(OhosPluginId.OHOS_HAR_PLUGIN) as OhosHarContext | undefined;
                const moduleContext = hapContext ?? harContext;
                if (!moduleContext) {
                    return;
                }
                const dependencies = moduleContext.getDependenciesOpt();
                delete dependencies[`flutter_native_${unselectedArchitecture}`];
                moduleContext.setDependenciesOpt(dependencies);

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

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[
        flutterHvigorPlugin(path.dirname(__dirname)),
        singleArchitectureFlutterPlugin,
    ]         /* Custom plugin to extend the functionality of Hvigor. */
}
