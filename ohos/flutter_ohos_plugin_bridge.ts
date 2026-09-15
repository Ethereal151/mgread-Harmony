/**
 * Keep Flutter OHOS plugin paths usable by Windows Hvigor.
 *
 * Flutter writes pub-cache plugin paths as absolute paths. When the project
 * and pub cache are on different drives, Hvigor rejects the resulting module
 * path. Cross-drive plugins are copied into the ignored OHOS project area;
 * same-drive plugins remain external and are converted by Hvigor to valid
 * relative paths.
 */
import fs from 'fs'
import path from 'path'

const nativeProjectPath = __dirname
const flutterProjectPath = path.dirname(nativeProjectPath)
const pluginDependenciesPath = path.join(flutterProjectPath, '.flutter-plugins-dependencies')
const pluginBridgePath = path.join(nativeProjectPath, 'plugins', '.flutter_ohos_plugins')
const legacyRootBridgePath = path.join(flutterProjectPath, '.flutter_ohos_plugins')
const legacyNativeBridgePath = path.join(nativeProjectPath, '.flutter_ohos_plugins')

function isInside(basePath: string, targetPath: string): boolean {
  const relativePath = path.relative(basePath, targetPath)
  return relativePath === '' || (
    !path.isAbsolute(relativePath) &&
    relativePath.split(path.sep).every(part => part !== '..')
  )
}

export function bridgeCrossDrivePlugins(): void {
  if (!fs.existsSync(pluginDependenciesPath)) {
    return
  }

  const dependenciesContent = fs.readFileSync(pluginDependenciesPath, 'utf8').replace(/^\uFEFF/, '')
  const dependencies = JSON.parse(dependenciesContent)
  let changed = false

  for (const plugin of dependencies.plugins?.ohos ?? []) {
    if (plugin.native_build === false || typeof plugin.path !== 'string') {
      continue
    }

    const configuredPluginRoot = path.isAbsolute(plugin.path)
      ? plugin.path
      : path.resolve(nativeProjectPath, plugin.path)
    if (!fs.existsSync(configuredPluginRoot)) {
      continue
    }

    const pluginRootPath = fs.lstatSync(configuredPluginRoot).isSymbolicLink()
      ? fs.realpathSync(configuredPluginRoot)
      : path.resolve(configuredPluginRoot)
    const bridgePath = path.join(pluginBridgePath, plugin.name)
    const needsBridge = path.isAbsolute(path.relative(nativeProjectPath, pluginRootPath)) ||
      isInside(legacyRootBridgePath, pluginRootPath) ||
      isInside(legacyNativeBridgePath, pluginRootPath)

    if (needsBridge && !isInside(pluginBridgePath, pluginRootPath)) {
      fs.mkdirSync(pluginBridgePath, { recursive: true })
      if (fs.existsSync(bridgePath)) {
        if (fs.lstatSync(bridgePath).isSymbolicLink()) {
          fs.unlinkSync(bridgePath)
        } else {
          fs.rmSync(bridgePath, { recursive: true, force: true })
        }
      }
      fs.cpSync(pluginRootPath, bridgePath, {
        recursive: true,
        filter: sourcePath => {
          const relativePath = path.relative(pluginRootPath, sourcePath)
          return !relativePath.split(path.sep).some(part =>
            part === 'build' || part === 'node_modules' || part === 'oh_modules')
        },
      })
      plugin.path = bridgePath
      changed = true
    } else if (isInside(pluginBridgePath, pluginRootPath) && plugin.path !== pluginRootPath) {
      plugin.path = pluginRootPath
      changed = true
    }
  }

  if (changed) {
    fs.writeFileSync(pluginDependenciesPath, `${JSON.stringify(dependencies, null, 2)}\n`)
  }
}
