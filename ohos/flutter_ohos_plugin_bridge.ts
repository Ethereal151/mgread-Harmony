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
const rootPackagePath = path.join(nativeProjectPath, 'oh-package.json5')

function isInside(basePath: string, targetPath: string): boolean {
  const relativePath = path.relative(basePath, targetPath)
  return relativePath === '' || (
    !path.isAbsolute(relativePath) &&
    relativePath.split(path.sep).every(part => part !== '..')
  )
}

function copyPluginTree(sourcePath: string, targetPath: string): void {
  const sourceStat = fs.lstatSync(sourcePath)
  if (sourceStat.isSymbolicLink()) {
    fs.symlinkSync(fs.readlinkSync(sourcePath), targetPath)
    return
  }
  if (!sourceStat.isDirectory()) {
    fs.copyFileSync(sourcePath, targetPath)
    return
  }

  fs.mkdirSync(targetPath, { recursive: true })
  for (const entry of fs.readdirSync(sourcePath)) {
    const sourceEntry = path.join(sourcePath, entry)
    const relativeEntry = path.relative(sourcePath, sourceEntry)
    if (relativeEntry.split(path.sep).some(part =>
      part === 'build' || part === 'node_modules' || part === 'oh_modules')) {
      continue
    }
    copyPluginTree(sourceEntry, path.join(targetPath, entry))
  }
}

function readLocalPluginOverride(pluginName: string): string | undefined {
  if (!fs.existsSync(rootPackagePath)) {
    return undefined
  }
  try {
    const packageConfig = JSON.parse(fs.readFileSync(rootPackagePath, 'utf8')) as {
      overrides?: Record<string, unknown>
    }
    const configuredOverride = packageConfig.overrides?.[pluginName]
    if (typeof configuredOverride !== 'string' || !configuredOverride.startsWith('file:')) {
      return undefined
    }
    const overridePath = configuredOverride.slice('file:'.length)
    const resolvedPath = path.isAbsolute(overridePath)
      ? overridePath
      : path.resolve(nativeProjectPath, overridePath)
    if (!fs.existsSync(resolvedPath)) {
      return undefined
    }
    // OHPM overrides point at the plugin's `ohos` directory, while Flutter's
    // plugin metadata points at the package root.
    return path.basename(resolvedPath).toLowerCase() === 'ohos'
      ? path.dirname(resolvedPath)
      : resolvedPath
  } catch {
    return undefined
  }
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

    const normalizedPluginPath = plugin.path.replace(/\\\\/gu, '\\')
    const configuredPluginRoot = readLocalPluginOverride(plugin.name) ?? (
      path.isAbsolute(normalizedPluginPath)
        ? normalizedPluginPath
        : path.resolve(nativeProjectPath, normalizedPluginPath)
    )
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
      copyPluginTree(pluginRootPath, bridgePath)
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
