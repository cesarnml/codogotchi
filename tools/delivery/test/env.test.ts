import { describe, expect, it } from 'bun:test';

import { parseDotEnv } from '../env';

describe('parseDotEnv', () => {
  it('parses dotenv content for missing process env hydration', () => {
    expect(
      parseDotEnv(
        [
          '# comment',
          'TELEGRAM_BOT_TOKEN=bot-token',
          'TELEGRAM_CHAT_ID="chat-id"',
          '',
        ].join('\n'),
      ),
    ).toEqual({
      TELEGRAM_BOT_TOKEN: 'bot-token',
      TELEGRAM_CHAT_ID: 'chat-id',
    });
  });
});
