// Klowop backend.
//
// Holds every secret so the app never does: the Anthropic key (assistant proxy),
// the Plaid secret (bank data), and the logic that verifies Sign in with Apple
// and StoreKit subscriptions. Each user's data is isolated by their Apple account.
//
// Stack: Express + better-sqlite3 (file db) + jose (token crypto) + Plaid.
// Deploy on any Node 18+ host (Railway/Render/Fly/VPS). State lives in klowop.db.

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const express = require('express');
const Database = require('better-sqlite3');
const jose = require('jose');
const { Configuration, PlaidApi, PlaidEnvironments } = require('plaid');

const PORT = process.env.PORT || 8484;
const SESSION_SECRET = process.env.SESSION_SECRET || '';
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY || '';
const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID || 'com.jaybznss.Klowop';
const ASSISTANT_MAX_TOKENS = parseInt(process.env.ASSISTANT_MAX_TOKENS || '16000', 10);
const ALLOW_FREE_PREMIUM = process.env.ALLOW_FREE_PREMIUM === 'true';

if (!SESSION_SECRET) console.warn('⚠️  SESSION_SECRET not set — sessions are insecure.');
if (!ANTHROPIC_API_KEY) console.warn('⚠️  ANTHROPIC_API_KEY not set — the assistant will fail.');

const sessionKey = new TextEncoder().encode(SESSION_SECRET || 'insecure-dev-secret');

// --- Database -------------------------------------------------------------

// DATABASE_PATH lets you point at a persistent volume (e.g. /data/klowop.db on
// Railway) so accounts survive redeploys. Defaults to a local file for dev.
const dbPath = process.env.DATABASE_PATH || path.join(__dirname, 'klowop.db');
fs.mkdirSync(path.dirname(dbPath), { recursive: true });
const db = new Database(dbPath);
db.pragma('journal_mode = WAL');
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    apple_sub TEXT UNIQUE NOT NULL,
    email TEXT,
    subscription_product TEXT,
    subscription_expires_at INTEGER,
    original_transaction_id TEXT,
    created_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS plaid_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    item_id TEXT NOT NULL,
    access_token TEXT NOT NULL,
    cursor TEXT,
    transactions TEXT,
    UNIQUE(user_id, item_id)
  );
`);

// --- Plaid ----------------------------------------------------------------

const plaid = new PlaidApi(new Configuration({
  basePath: PlaidEnvironments[process.env.PLAID_ENV || 'sandbox'],
  baseOptions: {
    headers: {
      'PLAID-CLIENT-ID': process.env.PLAID_CLIENT_ID,
      'PLAID-SECRET': process.env.PLAID_SECRET,
    },
  },
}));
const PLAID_COUNTRY_CODES = (process.env.PLAID_COUNTRY_CODES || 'US').split(',');

// --- Auth: Sign in with Apple --------------------------------------------

// Apple's public keys for verifying identity tokens (cached + auto-rotated by jose).
const APPLE_JWKS = jose.createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

async function issueSession(userId) {
  return new jose.SignJWT({ uid: userId })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('60d')
    .sign(sessionKey);
}

async function requireAuth(req, res, next) {
  try {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    const { payload } = await jose.jwtVerify(token, sessionKey);
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(payload.uid);
    if (!user) return res.status(401).json({ error: 'unknown user' });
    req.user = user;
    next();
  } catch {
    res.status(401).json({ error: 'not authenticated' });
  }
}

function hasActiveSubscription(user) {
  if (ALLOW_FREE_PREMIUM) return true;
  return user.subscription_expires_at && user.subscription_expires_at > Date.now();
}

function requireSubscription(req, res, next) {
  if (hasActiveSubscription(req.user)) return next();
  res.status(402).json({ error: 'subscription required', code: 'subscription_required' });
}

// --- StoreKit transaction verification ------------------------------------

// Strict verification validates the signed transaction's full certificate chain
// up to Apple's root CA (set STOREKIT_STRICT=true + provide the root cert for
// production). When off, we fall back to a lenient leaf-only check so local
// StoreKit testing (Xcode .storekit) — which isn't signed by Apple — still works.
function loadAppleRootCerts() {
  if (process.env.APPLE_ROOT_CA_BASE64) {
    return [Buffer.from(process.env.APPLE_ROOT_CA_BASE64, 'base64')];
  }
  const certPath = path.join(__dirname, 'certs', 'AppleRootCA-G3.cer');
  if (fs.existsSync(certPath)) return [fs.readFileSync(certPath)];
  return [];
}

let signedDataVerifier = null;
if (process.env.STOREKIT_STRICT === 'true') {
  try {
    const { SignedDataVerifier, Environment } = require('@apple/app-store-server-library');
    const roots = loadAppleRootCerts();
    if (!roots.length) throw new Error('Apple root CA not found (set APPLE_ROOT_CA_BASE64 or add certs/AppleRootCA-G3.cer)');
    const environment = process.env.APPLE_ENVIRONMENT === 'Production'
      ? Environment.PRODUCTION : Environment.SANDBOX;
    const appAppleId = process.env.APPLE_APP_APPLE_ID ? Number(process.env.APPLE_APP_APPLE_ID) : undefined;
    signedDataVerifier = new SignedDataVerifier(roots, false, environment, APPLE_BUNDLE_ID, appAppleId);
    console.log('StoreKit: strict Apple cert-chain verification enabled.');
  } catch (err) {
    console.error('⚠️  STOREKIT_STRICT requested but verifier setup failed:', err.message);
  }
} else {
  console.warn('⚠️  StoreKit strict verification OFF (dev mode). Set STOREKIT_STRICT=true for production.');
}

async function decodeTransaction(signedTransaction) {
  if (signedDataVerifier) {
    const payload = await signedDataVerifier.verifyAndDecodeTransaction(signedTransaction);
    return {
      productId: payload.productId,
      expiresDate: payload.expiresDate,
      originalTransactionId: payload.originalTransactionId,
      bundleId: payload.bundleId,
    };
  }
  // Lenient fallback: verify the JWS against its embedded leaf certificate only.
  const header = jose.decodeProtectedHeader(signedTransaction);
  const leaf = header.x5c && header.x5c[0];
  if (!leaf) throw new Error('missing certificate chain');
  const certPem = `-----BEGIN CERTIFICATE-----\n${leaf}\n-----END CERTIFICATE-----`;
  const publicKey = await jose.importX509(certPem, header.alg);
  const { payload } = await jose.compactVerify(signedTransaction, publicKey);
  return JSON.parse(new TextDecoder().decode(payload));
}

// --- App ------------------------------------------------------------------

const app = express();
app.use(express.json({ limit: '4mb' }));

app.get('/', (_req, res) => res.json({ ok: true, service: 'klowop-server' }));

// 1. Sign in with Apple: the app sends Apple's identity token; we verify it and
//    return our own long-lived session token used for every other request.
app.post('/auth/apple', async (req, res) => {
  try {
    const { identityToken } = req.body;
    if (!identityToken) return res.status(400).json({ error: 'identityToken required' });

    const { payload } = await jose.jwtVerify(identityToken, APPLE_JWKS, {
      issuer: 'https://appleid.apple.com',
      audience: APPLE_BUNDLE_ID,
    });
    const appleSub = payload.sub;
    const email = req.body.email || payload.email || null;

    let user = db.prepare('SELECT * FROM users WHERE apple_sub = ?').get(appleSub);
    if (!user) {
      const info = db.prepare(
        'INSERT INTO users (apple_sub, email, created_at) VALUES (?, ?, ?)'
      ).run(appleSub, email, Date.now());
      user = db.prepare('SELECT * FROM users WHERE id = ?').get(info.lastInsertRowid);
    } else if (email && !user.email) {
      db.prepare('UPDATE users SET email = ? WHERE id = ?').run(email, user.id);
    }

    const session = await issueSession(user.id);
    res.json({
      session,
      subscriptionActive: hasActiveSubscription(user),
    });
  } catch (err) {
    console.error('[auth/apple]', err.message);
    res.status(401).json({ error: 'invalid Apple token' });
  }
});

// 2. Assistant proxy: streams Claude responses using the server's key. The app
//    sends its messages/tools/system; we force the model and cap output so the
//    key can't be abused. The app keeps running its own tool loop client-side.
app.post('/api/assistant/messages', requireAuth, requireSubscription, async (req, res) => {
  try {
    const body = {
      model: 'claude-opus-4-8',
      max_tokens: Math.min(req.body.max_tokens || ASSISTANT_MAX_TOKENS, ASSISTANT_MAX_TOKENS),
      stream: true,
      thinking: { type: 'adaptive' },
      system: req.body.system,
      tools: req.body.tools,
      messages: req.body.messages,
    };

    const upstream = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(body),
    });

    res.status(upstream.status);
    res.setHeader('content-type', upstream.headers.get('content-type') || 'text/event-stream');
    if (!upstream.body) return res.end();
    for await (const chunk of upstream.body) res.write(chunk);
    res.end();
  } catch (err) {
    console.error('[assistant]', err.message);
    if (!res.headersSent) res.status(502).json({ error: 'assistant upstream failed' });
    else res.end();
  }
});

// 3. StoreKit 2: the app sends a signed transaction (JWS). We verify it (full
//    Apple cert-chain validation when STOREKIT_STRICT=true) and store the user's
//    entitlement (product + expiry).
app.post('/api/subscription/verify', requireAuth, async (req, res) => {
  try {
    const { signedTransaction } = req.body;
    if (!signedTransaction) return res.status(400).json({ error: 'signedTransaction required' });

    const tx = await decodeTransaction(signedTransaction);
    if (tx.bundleId && tx.bundleId !== APPLE_BUNDLE_ID) {
      return res.status(400).json({ error: 'bundle mismatch' });
    }

    db.prepare(`
      UPDATE users SET subscription_product = ?, subscription_expires_at = ?,
                       original_transaction_id = ? WHERE id = ?
    `).run(tx.productId || null, tx.expiresDate || null,
           tx.originalTransactionId || null, req.user.id);

    res.json({
      subscriptionActive: !!(tx.expiresDate && tx.expiresDate > Date.now()),
      productId: tx.productId,
      expiresDate: tx.expiresDate,
    });
  } catch (err) {
    console.error('[subscription]', err.message);
    res.status(400).json({ error: 'could not verify transaction' });
  }
});

// 4. Plaid — per-user, premium-gated. Hosted Link in the browser; secret stays here.
app.post('/api/plaid/create_link_token', requireAuth, requireSubscription, async (req, res) => {
  try {
    const response = await plaid.linkTokenCreate({
      user: { client_user_id: String(req.user.id) },
      client_name: 'Klowop',
      products: ['transactions'],
      country_codes: PLAID_COUNTRY_CODES,
      language: 'en',
      hosted_link: {},
    });
    res.json({
      link_token: response.data.link_token,
      hosted_link_url: response.data.hosted_link_url,
    });
  } catch (err) { fail(res, err); }
});

app.post('/api/plaid/complete_hosted_link', requireAuth, requireSubscription, async (req, res) => {
  try {
    const { link_token } = req.body;
    if (!link_token) return res.status(400).json({ error: 'link_token required' });
    const response = await plaid.linkTokenGet({ link_token });
    let publicToken = null;
    for (const session of response.data.link_sessions || []) {
      for (const result of session.results?.item_add_results || []) {
        if (result.public_token) publicToken = result.public_token;
      }
    }
    if (!publicToken) return res.json({ linked: false });

    const exchange = await plaid.itemPublicTokenExchange({ public_token: publicToken });
    db.prepare(`
      INSERT INTO plaid_items (user_id, item_id, access_token, cursor, transactions)
      VALUES (?, ?, ?, NULL, '[]')
      ON CONFLICT(user_id, item_id) DO NOTHING
    `).run(req.user.id, exchange.data.item_id, exchange.data.access_token);
    res.json({ linked: true });
  } catch (err) { fail(res, err); }
});

function userItems(userId) {
  return db.prepare('SELECT * FROM plaid_items WHERE user_id = ?').all(userId);
}

app.get('/api/plaid/accounts', requireAuth, requireSubscription, async (req, res) => {
  try {
    const accounts = [];
    for (const item of userItems(req.user.id)) {
      const response = await plaid.accountsBalanceGet({ access_token: item.access_token });
      const institution = await institutionName(response.data.item.institution_id);
      for (const account of response.data.accounts) {
        accounts.push({
          id: account.account_id,
          name: account.name,
          institution,
          type: mapAccountType(account.type),
          balance: account.balances.current ?? 0,
          currency: account.balances.iso_currency_code || 'USD',
        });
      }
    }
    res.json({ accounts });
  } catch (err) { fail(res, err); }
});

app.get('/api/plaid/transactions', requireAuth, requireSubscription, async (req, res) => {
  try {
    for (const item of userItems(req.user.id)) {
      let stored = JSON.parse(item.transactions || '[]');
      let cursor = item.cursor || undefined;
      let hasMore = true;
      while (hasMore) {
        const response = await plaid.transactionsSync({ access_token: item.access_token, cursor });
        const { added, modified, removed, next_cursor, has_more } = response.data;
        const removedIds = new Set(removed.map((t) => t.transaction_id));
        stored = stored.filter((t) => !removedIds.has(t.id));
        for (const tx of [...added, ...modified]) {
          const mapped = mapTransaction(tx);
          const idx = stored.findIndex((t) => t.id === mapped.id);
          if (idx >= 0) stored[idx] = mapped; else stored.push(mapped);
        }
        cursor = next_cursor;
        hasMore = has_more;
      }
      db.prepare('UPDATE plaid_items SET cursor = ?, transactions = ? WHERE id = ?')
        .run(cursor, JSON.stringify(stored), item.id);
    }

    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 90);
    const transactions = userItems(req.user.id)
      .flatMap((item) => JSON.parse(item.transactions || '[]'))
      .filter((t) => new Date(t.date) >= cutoff)
      .sort((a, b) => b.date.localeCompare(a.date));
    res.json({ transactions });
  } catch (err) { fail(res, err); }
});

app.get('/api/plaid/recurring', requireAuth, requireSubscription, async (req, res) => {
  try {
    const subscriptions = [];
    for (const item of userItems(req.user.id)) {
      const accountsResponse = await plaid.accountsGet({ access_token: item.access_token });
      const accountNames = Object.fromEntries(
        accountsResponse.data.accounts.map((a) => [a.account_id, a.name]));
      const response = await plaid.transactionsRecurringGet({
        access_token: item.access_token,
        account_ids: accountsResponse.data.accounts.map((a) => a.account_id),
      });
      for (const stream of response.data.outflow_streams) {
        if (stream.status === 'TOMBSTONED') continue;
        subscriptions.push({
          id: stream.stream_id,
          name: stream.merchant_name || stream.description,
          amount: Math.abs(stream.average_amount.amount ?? 0),
          cycle: mapFrequency(stream.frequency),
          next_date: stream.predicted_next_date || new Date().toISOString().slice(0, 10),
          account_name: accountNames[stream.account_id] || '',
          active: stream.is_active !== false,
        });
      }
    }
    res.json({ subscriptions });
  } catch (err) { fail(res, err); }
});

// 5. Account + data deletion (App Store requirement).
app.delete('/api/account', requireAuth, async (req, res) => {
  try {
    for (const item of userItems(req.user.id)) {
      try { await plaid.itemRemove({ access_token: item.access_token }); } catch { /* best effort */ }
    }
    db.prepare('DELETE FROM plaid_items WHERE user_id = ?').run(req.user.id);
    db.prepare('DELETE FROM users WHERE id = ?').run(req.user.id);
    res.json({ deleted: true });
  } catch (err) { fail(res, err); }
});

// --- Plaid mapping helpers ------------------------------------------------

const institutionCache = {};
async function institutionName(institutionId) {
  if (!institutionId) return 'Bank';
  if (institutionCache[institutionId]) return institutionCache[institutionId];
  try {
    const response = await plaid.institutionsGetById({
      institution_id: institutionId, country_codes: PLAID_COUNTRY_CODES,
    });
    institutionCache[institutionId] = response.data.institution.name;
    return institutionCache[institutionId];
  } catch { return 'Bank'; }
}

function mapAccountType(type) {
  switch (type) {
    case 'depository': return 'checking';
    case 'credit': return 'credit';
    case 'investment': return 'investment';
    default: return 'other';
  }
}

function mapTransaction(tx) {
  return {
    id: tx.transaction_id,
    merchant: tx.merchant_name || tx.name,
    amount: tx.amount,
    date: tx.date,
    category: tx.personal_finance_category?.primary?.replaceAll('_', ' ')
      ?.toLowerCase()?.replace(/\b\w/g, (c) => c.toUpperCase()) || 'Other',
    account_name: tx.account_id,
  };
}

function mapFrequency(frequency) {
  switch (frequency) {
    case 'WEEKLY': return 'weekly';
    case 'BIWEEKLY': return 'weekly';
    case 'ANNUALLY': return 'yearly';
    default: return 'monthly';
  }
}

function fail(res, err) {
  const message = err.response?.data?.error_message || err.message || 'unknown error';
  console.error('[klowop-server]', message);
  if (!res.headersSent) res.status(500).json({ error: message });
}

app.listen(PORT, () => {
  console.log(`Klowop backend listening on http://localhost:${PORT}`);
});
