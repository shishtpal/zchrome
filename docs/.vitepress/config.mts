import { defineConfig } from 'vitepress'

export default defineConfig({
  title: "zchrome",
  description: "Chrome DevTools Protocol client library for Zig",

  base: '/zchrome/',
  
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/logo.svg' }],
  ],

  themeConfig: {
    logo: '/logo.svg',
    
    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'API', link: '/api/browser' },
      { text: 'Examples', link: '/examples/' },
      { text: 'CLI', link: '/cli' },
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Introduction',
          items: [
            { text: 'What is zchrome?', link: '/guide/' },
            { text: 'Getting Started', link: '/guide/getting-started' },
            { text: 'Architecture', link: '/guide/architecture' },
          ]
        },
        {
          text: 'Core Concepts',
          items: [
            { text: 'Browser Management', link: '/guide/browser-management' },
            { text: 'Sessions & Targets', link: '/guide/sessions' },
            { text: 'Error Handling', link: '/guide/error-handling' },
            { text: 'Memory Management', link: '/guide/memory-management' },
          ]
        },
      ],
      '/api/': [
        {
          text: 'Core',
          items: [
            { text: 'Browser', link: '/api/browser' },
            { text: 'Connection', link: '/api/connection' },
            { text: 'Session', link: '/api/session' },
          ]
        },
        {
          text: 'Domains',
          items: [
            { text: 'Page', link: '/api/domains/page' },
            { text: 'DOM', link: '/api/domains/dom' },
            { text: 'Runtime', link: '/api/domains/runtime' },
            { text: 'Network', link: '/api/domains/network' },
            { text: 'Input', link: '/api/domains/input' },
            { text: 'Emulation', link: '/api/domains/emulation' },
            { text: 'Storage', link: '/api/domains/storage' },
            { text: 'Target', link: '/api/domains/target' },
            { text: 'Fetch', link: '/api/domains/fetch' },
            { text: 'Performance', link: '/api/domains/performance' },
          ]
        },
        {
          text: 'Utilities',
          items: [
            { text: 'JSON', link: '/api/util/json' },
            { text: 'Base64', link: '/api/util/base64' },
            { text: 'URL', link: '/api/util/url' },
          ]
        },
      ],
      '/examples/': [
        {
          text: 'Examples',
          items: [
            { text: 'Overview', link: '/examples/' },
            { text: 'Screenshots', link: '/examples/screenshots' },
            { text: 'PDF Generation', link: '/examples/pdf' },
            { text: 'DOM Manipulation', link: '/examples/dom' },
            { text: 'JavaScript Evaluation', link: '/examples/javascript' },
            { text: 'Network Interception', link: '/examples/network' },
          ]
        },
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/shishtpal/zchrome' }
    ],

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright 2026'
    },

    search: {
      provider: 'local'
    },

    outline: {
      level: [2, 3]
    },
  }
})
