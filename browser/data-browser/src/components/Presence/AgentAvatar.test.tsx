// @vitest-environment jsdom
import { render } from '@testing-library/react';
import { ThemeProvider } from 'styled-components';
import { expect, it, vi } from 'vitest';
import { AgentAvatar } from './AgentAvatar';

const useResource = vi.fn((_subject?: string) => ({}));

vi.mock('@tomic/react', async importOriginal => ({
  ...(await importOriginal<object>()),
  useResource: (s?: string) => useResource(s),
  useTitle: () => ['Drive'],
  useSubject: () => [undefined],
  useString: () => [undefined],
  useFileObjectUrl: () => undefined,
}));

it('does not request a mangled legacy drive subject', () => {
  const theme = {
    colors: { bg: '#fff', bg2: '#eee', main: '#00f' },
    animation: { duration: '0s' },
  } as never;
  const mangled = 'https://staging.atomicdata.dev/staging:/drive/zeg5rq7lz4d';

  render(
    <ThemeProvider theme={theme}>
      <AgentAvatar agentSubject={mangled} />
    </ThemeProvider>,
  );

  expect(useResource).toHaveBeenCalledWith(undefined);
  expect(useResource).not.toHaveBeenCalledWith(mangled);
});
