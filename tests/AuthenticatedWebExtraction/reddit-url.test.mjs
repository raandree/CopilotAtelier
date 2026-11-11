import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildRedditUrl,
  outputName,
  parseRequests
} from '../../skills/authenticated-web-extraction/bootstrap/lib/reddit-url.mjs';

test('builds the JSON URL of a thread', () => {
  assert.equal(
    buildRedditUrl('thread', 'travel', '1abc2de'),
    'https://www.reddit.com/r/travel/comments/1abc2de/.json?limit=500&depth=10&raw_json=1'
  );
});

test('builds the JSON URL of a subreddit search with an encoded query', () => {
  assert.equal(
    buildRedditUrl('search', 'travel', 'permits & passes'),
    'https://www.reddit.com/r/travel/search.json?q=permits+%26+passes&restrict_sr=1&sort=new&t=year&limit=25&raw_json=1'
  );
});

test('accepts the two-character names of older subreddits', () => {
  assert.match(buildRedditUrl('thread', 'de', 'abc'), /^https:\/\/www\.reddit\.com\/r\/de\/comments\/abc\/\.json\?/);
});

for (const subreddit of ['', 'a', '_lead', 'a b', '../api', 'sub/../../api', 'travel?x=1', 'x'.repeat(22), 'tr%61vel']) {
  test(`refuses the subreddit ${JSON.stringify(subreddit)}`, () => {
    assert.throws(() => buildRedditUrl('thread', subreddit, 'abc'), /subreddit/i);
  });
}

for (const subreddit of ['all', 'popular', 'random', 'randnsfw', 'myrandom', 'mod', 'friends', 'MOD', 'All']) {
  test(`refuses Reddit's own listing ${JSON.stringify(subreddit)}`, () => {
    assert.throws(() => buildRedditUrl('search', subreddit, 'night bus'), /subreddit/i);
  });
}

for (const postId of ['', 'ABC', '1abc/../x', 'id?x=1', 'x'.repeat(13), '1abc.json']) {
  test(`refuses the post id ${JSON.stringify(postId)}`, () => {
    assert.throws(() => buildRedditUrl('thread', 'travel', postId), /post id/i);
  });
}

for (const query of ['', '   ', 'x'.repeat(513)]) {
  test(`refuses the search query of length ${query.length}`, () => {
    assert.throws(() => buildRedditUrl('search', 'travel', query), /query/i);
  });
}

for (const kind of ['user', 'comments', 'api', 'THREAD', '']) {
  test(`refuses the request kind ${JSON.stringify(kind)}`, () => {
    assert.throws(() => buildRedditUrl(kind, 'travel', 'abc'), /kind/i);
  });
}

test('refuses values that are not strings', () => {
  assert.throws(() => buildRedditUrl('thread', ['travel'], 'abc'), /subreddit/i);
  assert.throws(() => buildRedditUrl('thread', 'travel', 123), /post id/i);
  assert.throws(() => buildRedditUrl('search', 'travel', null), /query/i);
});

test('every URL it builds stays on the one origin and the two JSON paths', () => {
  const urls = [
    buildRedditUrl('thread', 'travel', 'abc'),
    buildRedditUrl('search', 'travel', 'https://evil.example/ x')
  ];
  for (const url of urls) {
    const parsed = new URL(url);
    assert.equal(parsed.origin, 'https://www.reddit.com');
    assert.match(parsed.pathname, /^\/r\/[A-Za-z0-9_]+\/(comments\/[a-z0-9]+\/\.json|search\.json)$/);
  }
});

test('parses requests given as kind, subreddit, and value triples', () => {
  assert.deepEqual(parseRequests(['thread', 'travel', 'abc', 'search', 'travel', 'night bus']), [
    { kind: 'thread', subreddit: 'travel', value: 'abc' },
    { kind: 'search', subreddit: 'travel', value: 'night bus' }
  ]);
});

test('refuses an empty request list and an incomplete triple', () => {
  assert.throws(() => parseRequests([]), /usage/i);
  assert.throws(() => parseRequests(['thread', 'travel']), /usage/i);
});

test('refuses a bad triple before any request runs', () => {
  assert.throws(() => parseRequests(['thread', 'travel', 'abc', 'user', 'travel', 'abc']), /kind/i);
});

test('refuses a request repeated in the same run before any request runs', () => {
  assert.throws(() => parseRequests(['thread', 'travel', 'abc', 'thread', 'Travel', 'abc']), /duplicate/i);
  assert.throws(() => parseRequests(['search', 'travel', 'night bus', 'search', 'travel', 'night bus']), /duplicate/i);
});

test('gives every distinct search its own file name', () => {
  const names = ['Night bus', 'night-bus!', 'ночной автобус', 'дневной автобус'].map(value =>
    outputName({ kind: 'search', subreddit: 'travel', value })
  );
  assert.equal(new Set(names).size, names.length, names.join(', '));
});

test('names the output file after the request, in a safe character set', () => {
  assert.equal(outputName({ kind: 'thread', subreddit: 'travel', value: 'abc' }), 'thread-travel-abc.json');
  const name = outputName({ kind: 'search', subreddit: 'travel', value: 'Night bus / ../../x ' + 'y'.repeat(200) });
  assert.match(name, /^search-travel-[a-z0-9-]+\.json$/);
  assert.ok(name.length <= 90, `name too long: ${name.length}`);
});
