// Add to the array in eslint.config.js, after your general rules.
{
  files: ['src/features/*/ui/**/*.{ts,tsx}'],
  rules: {
    'no-restricted-syntax': ['error',
      {
        selector: 'CallExpression[callee.name=/^use[A-Z]/]:not([callee.name=/^use(Id|Ref|Memo|Callback|ImperativeHandle)$/])',
        message: 'ui/ is stateless. Move this to a connected component. Purely visual state needs a disable comment citing ADR-010.',
      },
      {
        selector: 'CallExpression[callee.object.name="React"][callee.property.name=/^use[A-Z]/]:not([callee.property.name=/^use(Id|Ref|Memo|Callback|ImperativeHandle)$/])',
        message: 'ui/ is stateless. Move this to a connected component. Purely visual state needs a disable comment citing ADR-010.',
      },
      {
        selector: 'MemberExpression[object.name="window"][property.name=/^(fetch|localStorage|sessionStorage|location)$/]',
        message: 'ui/ has no I/O or navigation. Take a value or a callback as a prop.',
      },
    ],
    'no-restricted-globals': ['error',
      ...['fetch', 'localStorage', 'sessionStorage', 'XMLHttpRequest', 'WebSocket', 'EventSource'].map((name) => ({
        name,
        message: 'ui/ has no I/O. Take a value or a callback as a prop.',
      })),
    ],
  },
},
