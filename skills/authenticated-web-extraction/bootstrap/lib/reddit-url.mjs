// Builds the only two Reddit URLs the reddit-read task may fetch: the JSON of a
// thread and of a subreddit search. Every other input throws, so text read
// through the signed-in session can never choose the next address it fetches.
import { createHash } from 'node:crypto';

const ORIGIN = 'https://www.reddit.com';
const SUBREDDIT = /^[A-Za-z0-9][A-Za-z0-9_]{1,20}$/;
// Reddit's own listings, not subreddits; mod and friends show the account's own data.
const LISTINGS = new Set(['all', 'popular', 'random', 'randnsfw', 'myrandom', 'mod', 'friends']);
const POST_ID = /^[a-z0-9]{1,12}$/;
const MAX_QUERY_LENGTH = 512;
const USAGE = 'Usage: reddit-read <thread|search> <subreddit> <post id|query> [<thread|search> <subreddit> <post id|query> ...]';

export function buildRedditUrl(kind, subreddit, value) {
  if (kind !== 'thread' && kind !== 'search') {
    throw new Error(`Unknown request kind ${JSON.stringify(kind)}: use thread or search.`);
  }
  if (typeof subreddit !== 'string' || !SUBREDDIT.test(subreddit)) {
    throw new Error(`Invalid subreddit name ${JSON.stringify(subreddit)}.`);
  }
  if (LISTINGS.has(subreddit.toLowerCase())) {
    throw new Error(`Invalid subreddit name ${JSON.stringify(subreddit)}: it is one of Reddit's own listings.`);
  }
  if (kind === 'thread') {
    if (typeof value !== 'string' || !POST_ID.test(value)) {
      throw new Error(`Invalid post id ${JSON.stringify(value)}: use the base-36 id from the thread URL.`);
    }
    return `${ORIGIN}/r/${subreddit}/comments/${value}/.json?limit=500&depth=10&raw_json=1`;
  }
  if (typeof value !== 'string' || value.trim().length === 0 || value.length > MAX_QUERY_LENGTH) {
    throw new Error(`Invalid search query: it must have 1 to ${MAX_QUERY_LENGTH} characters.`);
  }
  const query = new URLSearchParams({
    q: value,
    restrict_sr: '1',
    sort: 'new',
    t: 'year',
    limit: '25',
    raw_json: '1'
  });
  return `${ORIGIN}/r/${subreddit}/search.json?${query}`;
}

export function parseRequests(args) {
  if (!Array.isArray(args) || args.length === 0 || args.length % 3 !== 0) {
    throw new Error(USAGE);
  }
  const requests = [];
  const names = new Set();
  for (let index = 0; index < args.length; index += 3) {
    const [kind, subreddit, value] = args.slice(index, index + 3);
    buildRedditUrl(kind, subreddit, value);
    const request = { kind, subreddit, value };
    const name = outputName(request);
    if (names.has(name)) {
      throw new Error(`Duplicate request: ${kind} ${subreddit} ${JSON.stringify(value)} appears twice.`);
    }
    names.add(name);
    requests.push(request);
  }
  return requests;
}

// Search names carry a hash of the exact query, because the readable part is
// lossy: "Night bus" and "night-bus!", or any two non-Latin queries, would
// otherwise share a file and overwrite each other.
export function outputName(request) {
  const subreddit = request.subreddit.toLowerCase();
  if (request.kind === 'thread') {
    return `thread-${subreddit}-${request.value}.json`;
  }
  const readable = request.value.toLowerCase().replace(/[^a-z0-9]+/g, '-').slice(0, 60).replace(/^-+|-+$/g, '') || 'query';
  const digest = createHash('sha256').update(request.value, 'utf8').digest('hex').slice(0, 8);
  return `search-${subreddit}-${readable}-${digest}.json`;
}
