/** The Linux window icon resolves beside the Electron resources in both run modes. */

import { join } from 'node:path'
import { describe, expect, it, onTestFinished, vi } from 'vitest'

const electron = vi.hoisted(() => ({
  state: { isPackaged: true, appPath: '/desktop-app', resourcesPath: '/desktop-resources' },
}))
vi.mock('electron', () => ({
  app: {
    get isPackaged() { return electron.state.isPackaged },
    getAppPath: () => electron.state.appPath,
  },
}))

const { linuxWindowIconPath } = await import('../src/window-icon.ts')

describe('desktop window icon path', () => {
  it('reads the packaged icon shipped beside the Electron resources', () => {
    vi.stubGlobal('process', { ...process, resourcesPath: electron.state.resourcesPath })
    onTestFinished(() => { vi.unstubAllGlobals() })
    expect(linuxWindowIconPath()).toBe(join(electron.state.resourcesPath, 'icon.png'))
  })

  it('reads the development icon from the app root resources', () => {
    electron.state.isPackaged = false
    expect(linuxWindowIconPath()).toBe(join(electron.state.appPath, 'resources', 'icon.png'))
  })
})
