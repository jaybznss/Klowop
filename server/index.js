// Klowop companion server.
//
// Plaid requires a server-side secret to exchange Link public tokens for access
// tokens, so that exchange lives here instead of in the iOS app. State (item
// access tokens, sync cursors, cached transactions) is stored in data.json next
// to this file — fine for personal use; swap for a real database if you ever
// host this for more than yourself.

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const express = require('express');
const { Configuration, PlaidApi, PlaidEnvironments } = require('plaid');

const DATA_FILE = path.join(__dirname, 'data.json');
const PORT = process.env.PORT || 8484;

const plaid = new PlaidApi(new Configuration({
  basePath: PlaidEnvironments[process.env.PLAID_ENV || 'sandbox'],
  baseOptions: {
    headers: {
      'PLAID-CLIENT-ID': process.env.PLAID_CLIENT_ID,
      'PLAID-SECRET': process.env.PLAID_SECRET,
    },
  },
}));

function loadData() {
  try {
    return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
  } catch {
    return { items: [] }; // items: [{ access_token, institution, cursor, transactions: [] }]
  }
}

function saveData(data) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
}

const app = express();
app.use(express.json());

app.get('/', (_req, res) => res.json({ ok: true, service: 'klowop-server' }));

// 1. The app asks for a Hosted Link session — Plaid's linking UI runs in the
//    browser, so the iOS app needs no native Plaid SDK.
app.post('/api/create_link_token', async (_req, res) => {
  try {
    const response = await plaid.linkTokenCreate({
      user: { client_user_id: 'klowop-user' },
      client_name: 'Klowop',
      products: ['transactions'],
      country_codes: (process.env.PLAID_COUNTRY_CODES || 'US').split(','),
      language: 'en',
      hosted_link: {},
    });
    res.json({
      link_token: response.data.link_token,
      hosted_link_url: response.data.hosted_link_url,
    });
  } catch (err) {
    fail(res, err);
  }
});

// 2. After the user finishes in the browser, the app asks us to complete the
//    session: fetch the session result, exchange the public token, store the item.
app.post('/api/complete_hosted_link', async (req, res) => {
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
    const data = loadData();
    if (!data.items.some((item) => item.item_id === exchange.data.item_id)) {
      data.items.push({
        access_token: exchange.data.access_token,
        item_id: exchange.data.item_id,
        cursor: null,
        transactions: [],
      });
      saveData(data);
    }
    res.json({ linked: true });
  } catch (err) {
    fail(res, err);
  }
});

// 3. Account balances across all linked items.
app.get('/api/accounts', async (_req, res) => {
  try {
    const data = loadData();
    const accounts = [];
    for (const item of data.items) {
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
  } catch (err) {
    fail(res, err);
  }
});

// 4. Transactions via /transactions/sync (cursor kept per item).
app.get('/api/transactions', async (_req, res) => {
  try {
    const data = loadData();
    for (const item of data.items) {
      let hasMore = true;
      while (hasMore) {
        const response = await plaid.transactionsSync({
          access_token: item.access_token,
          cursor: item.cursor || undefined,
        });
        const { added, modified, removed, next_cursor, has_more } = response.data;
        const removedIds = new Set(removed.map((t) => t.transaction_id));
        item.transactions = item.transactions.filter((t) => !removedIds.has(t.id));
        for (const tx of [...added, ...modified]) {
          const mapped = mapTransaction(tx);
          const idx = item.transactions.findIndex((t) => t.id === mapped.id);
          if (idx >= 0) item.transactions[idx] = mapped;
          else item.transactions.push(mapped);
        }
        item.cursor = next_cursor;
        hasMore = has_more;
      }
    }
    saveData(data);

    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 90);
    const transactions = data.items
      .flatMap((item) => item.transactions)
      .filter((t) => new Date(t.date) >= cutoff)
      .sort((a, b) => b.date.localeCompare(a.date));
    res.json({ transactions });
  } catch (err) {
    fail(res, err);
  }
});

// 5. Subscriptions: Plaid's recurring transaction streams.
app.get('/api/recurring', async (_req, res) => {
  try {
    const data = loadData();
    const subscriptions = [];
    for (const item of data.items) {
      const accountsResponse = await plaid.accountsGet({ access_token: item.access_token });
      const accountNames = Object.fromEntries(
        accountsResponse.data.accounts.map((a) => [a.account_id, a.name]),
      );
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
  } catch (err) {
    fail(res, err);
  }
});

const institutionCache = {};
async function institutionName(institutionId) {
  if (!institutionId) return 'Bank';
  if (institutionCache[institutionId]) return institutionCache[institutionId];
  try {
    const response = await plaid.institutionsGetById({
      institution_id: institutionId,
      country_codes: (process.env.PLAID_COUNTRY_CODES || 'US').split(','),
    });
    institutionCache[institutionId] = response.data.institution.name;
    return institutionCache[institutionId];
  } catch {
    return 'Bank';
  }
}

function mapAccountType(type) {
  switch (type) {
    case 'depository': return 'checking';
    case 'credit': return 'credit';
    case 'investment': return 'investment';
    case 'loan': return 'other';
    default: return 'other';
  }
}

function mapTransaction(tx) {
  return {
    id: tx.transaction_id,
    merchant: tx.merchant_name || tx.name,
    amount: tx.amount, // Plaid: positive = money out
    date: tx.date,
    category: tx.personal_finance_category?.primary?.replaceAll('_', ' ')
      ?.toLowerCase()
      ?.replace(/\b\w/g, (c) => c.toUpperCase()) || 'Other',
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
  res.status(500).json({ error: message });
}

app.listen(PORT, () => {
  console.log(`Klowop companion server listening on http://localhost:${PORT}`);
  if (!process.env.PLAID_CLIENT_ID || !process.env.PLAID_SECRET) {
    console.warn('⚠️  PLAID_CLIENT_ID / PLAID_SECRET not set — copy .env.example to .env first.');
  }
});
