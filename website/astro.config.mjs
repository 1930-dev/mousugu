// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Static, zero-client-JS marketing site served at the apex.
// The Sparkle appcast ships from public/appcast.xml → /appcast.xml,
// which is what SUFeedURL in Config/Direct-Info.plist points at.
export default defineConfig({
  site: 'https://mousugu.app',
  trailingSlash: 'never',
  integrations: [sitemap()],
  build: {
    format: 'file',
    inlineStylesheets: 'always',
  },
});
