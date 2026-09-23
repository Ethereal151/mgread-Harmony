import fs from 'fs';
import path from 'path'
import { appTasks, OhosAppContext, OhosHarContext, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { flutterHvigorPlugin } from 'flutter-hvigor-plugin';
import { bridgeCrossDrivePlugins } from './flutter_ohos_plugin_bridge';

bridgeCrossDrivePlugins();

function pruneNonOhosFlutterOutputs(nodePath: string): void {
    const rawfilePath = path.join(nodePath, 'src', 'main', 'resources', 'rawfile');
    const runtimeRoot = path.join(rawfilePath, 'flutter_assets', 'packages', 'mgread_plugin_runtime', 'assets', 'runtime');
    for (const platform of ['android', 'windows-x64', 'macos-arm64']) {
        const platformPath = path.join(runtimeRoot, platform);
        if (fs.existsSync(platformPath)) {
            fs.rmSync(platformPath, { recursive: true, force: true });
        }
    }

    const x64LibsPath = path.join(nodePath, 'libs', 'x86_64');
    if (fs.existsSync(x64LibsPath)) {
        fs.rmSync(x64LibsPath, { recursive: true, force: true });
    }

}

const arm64OnlyFlutterPlugin: HvigorPlugin = {
    pluginId: 'mgread-arm64-only-flutter',
    apply(rootNode: HvigorNode) {
        rootNode.afterNodeEvaluate(node => {
            const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
            const overrides = appContext.getOverrides() ?? {};
            delete overrides.flutter_native_x86_64;
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
                delete dependencies.flutter_native_x86_64;
                moduleContext.setDependenciesOpt(dependencies);

                if (subNode.getNodeName() === 'entry') {
                    const flutterTask = node.getTaskByName('default@FlutterTask');
                    flutterTask?.afterRun(() => pruneNonOhosFlutterOutputs(node.getNodePath()));
                }
            });
        });
    },
};

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[
        flutterHvigorPlugin(path.dirname(__dirname)),
        arm64OnlyFlutterPlugin,
    ]         /* Custom plugin to extend the functionality of Hvigor. */
}
