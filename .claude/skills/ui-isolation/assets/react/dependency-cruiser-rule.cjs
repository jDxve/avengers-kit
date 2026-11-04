// Add to `forbidden` in .dependency-cruiser.cjs. Extend pathNot only with purely visual packages.
{
  name: 'ui-is-presentational',
  severity: 'error',
  comment: 'features/x/ui takes props and fires callbacks. Wire state in features/x/components.',
  from: { path: '^src/features/([^/]+)/ui/' },
  to: {
    pathNot: [
      '^src/features/$1/ui/',
      '^src/features/$1/types\\.ts$',
      '^src/components/ui/',
      '^src/lib/format/',
      '^src/styles/',
      'node_modules/(react|react-dom|@types/react|clsx|lucide-react)/',
    ],
  },
},
