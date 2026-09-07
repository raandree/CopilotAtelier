import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.mjs',
  timeout: 60_000,
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  use: {
    // Uses the installed Microsoft Edge rather than downloading a browser, so
    // the optional package does not pull a browser bundle into the repository.
    channel: 'msedge',
    headless: true,
    screenshot: 'off',
    video: 'off'
  },
  projects: [
    {
      name: 'desktop',
      use: { ...devices['Desktop Edge'], channel: 'msedge', viewport: { width: 1440, height: 900 } }
    },
    {
      name: 'mobile',
      use: { ...devices['Pixel 7'], channel: 'msedge', isMobile: false, viewport: { width: 390, height: 844 } }
    }
  ]
})
