import { moderateMessage } from '../src/modules/chat/moderation';
const tests = [
  'Hi, I am on my way',
  'Call me on 0712 345 678',
  'my email is john at gmail dot com',
  'zero seven one two three four five six seven',
  'pay me directly via mpesa',
  'check www.scam.link',
  'you idiot fuck off',
];
for (const t of tests) {
  const r = moderateMessage(t);
  console.log(`${r.allowed ? 'ALLOW ' : 'BLOCK '} [${r.reason ?? 'ok'}]  "${t}"`);
}
process.exit(0);
