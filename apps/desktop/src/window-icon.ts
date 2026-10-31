/** Linux window icon resolution shared by every top-level application window. */

import { join } from 'node:path'
import { app } from 'electron'

/**
 * Resolve the application icon for the `BrowserWindow` `icon` option.
 * Linux draws the title bar, taskbar, and Alt-Tab icon from the window options, so
 * the packaged tree ships the icon beside the Electron resources and development
 * runs read the app root's source asset. Windows and macOS take window icons from
 * the executable and the application bundle instead and never call this.
 * @returns absolute path of the platform-neutral icon PNG.
 */
export function linuxWindowIconPath(): string {
  return app.isPackaged ? join(process.resourcesPath, 'icon.png') : join(app.getAppPath(), 'resources', 'icon.png')
}
