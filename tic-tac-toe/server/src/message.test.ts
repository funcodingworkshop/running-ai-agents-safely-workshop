import { describe, it, expect } from 'vitest';
import { getMessage } from './message.js';

describe('getMessage', () => {
  it('returns the server greeting', () => {
    expect(getMessage()).toBe('Hello from the TypeScript Server!');
  });
});
