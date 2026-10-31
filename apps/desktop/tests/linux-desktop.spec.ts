/** Linux unsigned packaging associates running windows and the local install entry with the product icon. */

import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

describe('linux desktop packaging', () => {
  it('derives window association from the launcher entry name', async () => {
    const { createElectronBuilderConfig } = await import('../scripts/electron-builder-config.mjs')
    const config = createElectronBuilderConfig({
      DSH_DESKTOP_APP_ID: 'com.example.linux',
      DSH_DESKTOP_TARGET_PLATFORM: 'linux',
      DSH_DESKTOP_TARGET_ARCH: 'x64',
      DSH_DESKTOP_UNSIGNED: '1',
    }, 'linux', 'x64')
    // Electron reads desktopName from the packaged manifest for app_id / WM_CLASS; electron-builder
    // mirrors it as the entry filename and StartupWMClass, so all three agree on deepseek-harness.
    expect(config.extraMetadata.desktopName).toBe('deepseek-harness.desktop')
    expect(config.linux).toMatchObject({ executableName: 'deepseek-harness', syncDesktopName: true })
    expect(config.linux.icon).toMatch(/[\\/]resources[\\/]icon\.png$/u)
  })

  it('keeps the local install entry associated with the running window', () => {
    const script = readFileSync(new URL('../scripts/install-linux-desktop.sh', import.meta.url), 'utf8')
    expect(script).toContain('StartupWMClass=deepseek-harness')
    expect(script).toContain('Icon=$ROOT/current/resources/icon.png')
  })
})
