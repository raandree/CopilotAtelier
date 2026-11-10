// Reads Reddit threads and subreddit searches as JSON through the signed-in
// persistent profile. Run it in a visible window; it refuses --headless.
//   node scripts/extract.mjs reddit-read thread <subreddit> <post id> [search <subreddit> "<query>" ...]
// Every address comes from lib/reddit-url.mjs. Nothing read from Reddit is ever
// fetched, opened, or followed, and the task only reads: no post, vote, or message.
// It saves only public fields, and its messages never repeat text from Reddit.
import fs from 'node:fs';
import path from 'node:path';
import { buildRedditUrl, outputName, parseRequests } from '../lib/reddit-url.mjs';

const PAUSE_MS = 1500;
const REQUEST_TIMEOUT_MS = 30000;  // a thread of 500 comments arrives in a few seconds
const POST_FIELDS = ['id', 'title', 'selftext', 'author', 'created_utc', 'score', 'num_comments'];
const COMMENT_FIELDS = ['id', 'author', 'body', 'created_utc', 'score'];
const REASON = /^[a-z_]{1,40}$/;  // Reddit's refusal codes, such as private or quarantined

function pick(source, fields) {
  const kept = {};
  for (const field of fields) {
    if (source && Object.hasOwn(source, field)) {
      kept[field] = source[field];
    }
  }
  return kept;
}

function children(listing) {
  return Array.isArray(listing?.data?.children) ? listing.data.children : [];
}

function publicComments(listing) {
  const comments = [];
  for (const child of children(listing)) {
    if (child?.kind === 't1') {
      comments.push({ ...pick(child.data, COMMENT_FIELDS), replies: publicComments(child.data?.replies) });
    } else if (child?.kind === 'more') {
      comments.push({ more: Number(child.data?.count) || 0 });
    }
  }
  return comments;
}

// Drops the modhash, the account's own votes, saves, and visits, and every link.
export function toPublic(request, json) {
  if (request.kind === 'thread') {
    const [postListing, commentListing] = Array.isArray(json) ? json : [];
    const post = children(postListing).find(child => child?.kind === 't3');
    return {
      kind: 'thread',
      subreddit: request.subreddit,
      post: post ? pick(post.data, POST_FIELDS) : null,
      comments: publicComments(commentListing)
    };
  }
  return {
    kind: 'search',
    subreddit: request.subreddit,
    query: request.value,
    posts: children(json).filter(child => child?.kind === 't3').map(child => pick(child.data, POST_FIELDS))
  };
}

function refusalReason(body) {
  try {
    const reason = JSON.parse(body)?.reason;
    return typeof reason === 'string' && REASON.test(reason) ? reason : '';
  } catch {
    return '';
  }
}

export default async function redditRead({ context, page, args, outDir, headless = false }) {
  if (headless) {
    throw new Error('reddit-read runs only in a visible window: run it again without --headless.');
  }
  const requests = parseRequests(args);

  const cookies = await context.cookies('https://www.reddit.com');
  if (!cookies.some(cookie => cookie.name === 'reddit_session')) {
    throw new Error('Not signed in to Reddit. Run: node scripts/open.mjs https://www.reddit.com/login/');
  }

  // The in-page fetch must run on Reddit's origin to send the session cookie.
  await page.goto('https://www.reddit.com/robots.txt', { waitUntil: 'domcontentloaded' });

  const targetDir = path.join(outDir, 'reddit');
  fs.mkdirSync(targetDir, { recursive: true });

  for (const [index, request] of requests.entries()) {
    if (index > 0) {
      await new Promise(resolve => setTimeout(resolve, PAUSE_MS));
    }
    const url = buildRedditUrl(request.kind, request.subreddit, request.value);
    const response = await page.evaluate(async ({ target, timeoutMs }) => {
      try {
        const res = await fetch(target, {
          method: 'GET',
          credentials: 'same-origin',
          redirect: 'error',
          headers: { Accept: 'application/json' },
          signal: AbortSignal.timeout(timeoutMs)
        });
        return { status: res.status, type: res.headers.get('content-type') || '', body: await res.text() };
      } catch (error) {
        return { status: 0, failure: error?.name === 'TimeoutError' ? 'timeout' : 'failed' };
      }
    }, { target: url, timeoutMs: REQUEST_TIMEOUT_MS });

    if (response.failure === 'timeout') {
      throw new Error(`Reddit did not answer within ${REQUEST_TIMEOUT_MS / 1000} s for ${url}. Stop here; rerun the remaining requests later.`);
    }
    if (response.failure) {
      throw new Error(`The request for ${url} failed or Reddit redirected it, and redirects are refused. Stop here; open the thread in the visible window to see why.`);
    }
    if (response.status !== 200) {
      const reason = refusalReason(response.body);
      throw new Error(reason
        ? `Reddit answered HTTP ${response.status} (reason: ${reason}) for ${url}. Stop here; the account cannot read it, so leave it out when you rerun the remaining requests.`
        : `Reddit answered HTTP ${response.status} for ${url}. Stop here; after a 403 or 429, wait before rerunning the remaining requests.`);
    }
    if (!/^application\/json\b/i.test(response.type)) {
      throw new Error(`Reddit answered HTTP 200 without JSON for ${url}, probably a sign-in or interstitial page. Stop here and run check-logins.`);
    }
    let json;
    try {
      json = JSON.parse(response.body);
    } catch {
      throw new Error(`Reddit answered HTTP 200 with unreadable JSON for ${url}. Stop here; rerun the remaining requests later.`);
    }

    const file = path.join(targetDir, outputName(request));
    fs.writeFileSync(file, JSON.stringify(toPublic(request, json), null, 2), 'utf8');
    console.log(`Wrote ${file}`);
  }
}
