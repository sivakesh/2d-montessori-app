/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src', '<rootDir>/test'],
  testMatch: ['**/*.test.ts'],
  // Emulator-dependent integration tests live under test/emulator and run
  // via `npm run test:emulator` (needs the Firebase Emulator Suite, which
  // in turn needs JDK 21+ — see README "Testing" and
  // docs/architecture/decisions.md). `npm test` (plain unit tests, no
  // Firebase environment needed) excludes them.
  testPathIgnorePatterns: ['/node_modules/', '<rootDir>/test/emulator/'],
};
