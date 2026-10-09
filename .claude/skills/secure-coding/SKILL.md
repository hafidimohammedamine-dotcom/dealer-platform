---
name: "secure-coding"
description: "Secure web and desktop application development. Use when writing authentication, authorization, API endpoints, form handling, database queries, file uploads, Electron apps, Tauri apps, IPC handlers, cryptography, secrets management, security headers, input validation, or when reviewing code for vulnerabilities. Covers OWASP Top 10, XSS, CSRF, SQL injection, SSRF, command injection, path traversal, and desktop app security."
---

# Application Security

You are a security-focused engineer. Every line of code you write or review must defend against real attack vectors. You don't add security theater — you implement defenses that stop actual exploits.

Read the detailed reference files in `${CLAUDE_SKILL_DIR}` for comprehensive patterns:

- `web-security.md` — XSS, CSRF, injection, SSRF, path traversal, input validation, security headers
- `auth-and-secrets.md` — Authentication, JWT, OAuth2 PKCE, API keys, password hashing, secrets management
- `desktop-security.md` — Electron and Tauri hardening, IPC security, auto-updater, deep links, sandboxing
- `database-and-deps.md` — SQL injection prevention, ORM security, connection management, dependency supply chain

## Security-First Mindset

When writing or reviewing code, always ask:

1. **What can an attacker control?** — Every external input is hostile: URL params, headers, cookies, form data, file uploads, WebSocket messages, deep links, IPC messages
2. **What's the blast radius?** — If this is exploited, what's the worst case? RCE > data theft > DoS > information leak
3. **Am I validating at the boundary?** — Validate where data enters the system, not deep inside

## Quick Reference: The Non-Negotiables

### Web Apps
```
✗ NEVER concatenate user input into SQL, HTML, shell commands, or URLs
✗ NEVER use eval(), Function(), innerHTML with untrusted data
✗ NEVER store secrets in code, localStorage, or client-accessible locations
✗ NEVER disable CORS, CSP, or same-origin protections without justification
✗ NEVER use MD5/SHA1 for passwords — use Argon2id or bcrypt
✗ NEVER use Math.random() for security tokens — use crypto.randomBytes()
✗ NEVER trust client-side validation alone

✓ ALWAYS use parameterized queries (prepared statements, ORMs)
✓ ALWAYS set HttpOnly, Secure, SameSite on auth cookies
✓ ALWAYS escape output in the context it's rendered (HTML, JS, URL, CSS)
✓ ALWAYS validate and sanitize input at system boundaries
✓ ALWAYS use HTTPS + HSTS in production
✓ ALWAYS implement rate limiting on auth endpoints
✓ ALWAYS use CSP headers — start with default-src 'self'
```

### Desktop Apps (Electron)
```
✗ NEVER enable nodeIntegration in renderer
✗ NEVER disable contextIsolation or webSecurity
✗ NEVER expose raw ipcRenderer to renderer process
✗ NEVER use the remote module (deprecated, dangerous)
✗ NEVER load remote URLs without URL validation

✓ ALWAYS enable contextIsolation + sandbox
✓ ALWAYS use contextBridge with minimal, validated API surface
✓ ALWAYS validate IPC sender identity and message schema
✓ ALWAYS validate deep link URLs before processing
✓ ALWAYS use code signing for distribution
```

### Desktop Apps (Tauri)
```
✗ NEVER allow unrestricted shell execution
✗ NEVER use broad file system scopes
✗ NEVER skip command input validation (even with Rust types)

✓ ALWAYS use invoke() pattern (not raw events) for sensitive ops
✓ ALWAYS configure restrictive scopes (fs, http, shell)
✓ ALWAYS set CSP in tauri.conf.json
✓ ALWAYS define per-window capabilities (least privilege)
```

## Vulnerability Response Patterns

When you detect a vulnerability in code:

| Vulnerability | Immediate Fix |
|--------------|---------------|
| SQL injection | Switch to parameterized queries |
| XSS (reflected/stored) | Escape output + add CSP header |
| Command injection | Use spawn() with array args, never exec() with strings |
| Path traversal | Resolve path, verify it starts with allowed directory |
| CSRF | Add SameSite=Strict cookies + CSRF tokens |
| SSRF | Validate URL against allowlist, block private IP ranges |
| Insecure auth cookie | Add HttpOnly, Secure, SameSite flags |
| Hardcoded secret | Move to env var, rotate the exposed secret |
| Weak password hash | Migrate to Argon2id with proper parameters |
| Electron nodeIntegration | Set false + enable contextIsolation + sandbox |

## Critical Rules

1. **Validate at boundaries** — Every system edge (HTTP, IPC, file read, DB query) needs validation
2. **Defense in depth** — Never rely on a single security control; layer defenses
3. **Principle of least privilege** — Grant minimum access needed; restrict tools, scopes, permissions
4. **Fail closed** — Errors should deny access, not grant it; default to rejection
5. **Never trust the client** — All client data is attacker-controlled until validated server-side
6. **Secrets never in code** — Use env vars, vaults, or OS keychains; rotate exposed secrets immediately
7. **Escape for the output context** — HTML entities for HTML, parameterized for SQL, array args for shell
8. **Use established crypto** — Argon2id for passwords, AES-256-GCM for encryption, crypto.randomBytes() for tokens
9. **Pin dependencies** — Use lock files, audit regularly, verify integrity with SRI for CDN resources
10. **Log security events** — Failed logins, permission denials, input validation failures; never log secrets

## Using This Skill

If `$ARGUMENTS` specifies an area (e.g., `/security authentication`), read the relevant reference file and focus there. Otherwise, apply security principles to whatever code you're currently writing or reviewing.

When reviewing existing code, scan for the vulnerability patterns in the reference files and flag each finding with severity (Critical/High/Medium/Low) and a concrete fix.


# Appendix: Bundled Reference Files


---

## Reference file: `auth-and-secrets.md`

# Authentication & Secrets Management Reference

## Password Hashing

### Argon2id (Recommended — 2025 standard)
```javascript
const argon2 = require('argon2');

async function hashPassword(password) {
  return argon2.hash(password, {
    type: argon2.argon2id,
    memoryCost: 65536,   // 64 MB
    timeCost: 3,
    parallelism: 4
  });
}

async function verifyPassword(hash, password) {
  return argon2.verify(hash, password);
}

// Login — never reveal which field was wrong
async function login(email, password) {
  const user = await db.findUser(email);
  if (!user || !(await verifyPassword(user.passwordHash, password))) {
    throw new Error('Invalid credentials'); // Same message for both cases
  }
  return user;
}
```

### bcrypt (Acceptable alternative)
```javascript
const bcrypt = require('bcrypt');
const SALT_ROUNDS = 12; // Minimum 10, prefer 12+

const hash = await bcrypt.hash(password, SALT_ROUNDS);
const valid = await bcrypt.compare(password, hash);
```

**Never use:** MD5, SHA1, SHA256 (without key stretching), or plain text for passwords.

---

## JWT Authentication

### Short-Lived Access + Refresh Token Pattern
```javascript
const jwt = require('jsonwebtoken');

function createAccessToken(userId) {
  return jwt.sign({ sub: userId }, process.env.JWT_SECRET, {
    expiresIn: '15m',
    algorithm: 'HS256'
  });
}

function createRefreshToken(userId) {
  return jwt.sign({ sub: userId }, process.env.REFRESH_SECRET, {
    expiresIn: '7d',
    algorithm: 'HS256'
  });
}

// Middleware
function authenticate(req, res, next) {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'No token' });

  try {
    req.user = jwt.verify(token, process.env.JWT_SECRET);
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expired' });
    }
    return res.status(401).json({ error: 'Invalid token' });
  }
}

// Refresh endpoint — refresh token in HttpOnly cookie
app.post('/auth/refresh', (req, res) => {
  const refreshToken = req.cookies.refreshToken;
  try {
    const decoded = jwt.verify(refreshToken, process.env.REFRESH_SECRET);
    const newAccess = createAccessToken(decoded.sub);
    res.json({ accessToken: newAccess });
  } catch {
    res.clearCookie('refreshToken');
    res.status(401).json({ error: 'Invalid refresh token' });
  }
});
```

### JWT Security Rules
- Access tokens: 15 minutes max
- Refresh tokens: HttpOnly cookie, 7 days max, rotate on use
- Never store JWTs in localStorage (XSS-accessible)
- Always verify `algorithm` — don't accept `none`
- Include `sub` (subject), `iat` (issued at), `exp` (expiry) claims

---

## OAuth2 with PKCE

```javascript
const crypto = require('crypto');

// Generate PKCE values
const codeVerifier = crypto.randomBytes(32).toString('base64url');
const codeChallenge = crypto.createHash('sha256').update(codeVerifier).digest('base64url');

// Step 1: Redirect to provider
app.get('/auth/login', (req, res) => {
  const state = crypto.randomBytes(32).toString('base64url');
  req.session.oauthState = state;
  req.session.codeVerifier = codeVerifier;

  const params = new URLSearchParams({
    client_id: process.env.OAUTH_CLIENT_ID,
    redirect_uri: 'https://myapp.com/auth/callback',
    response_type: 'code',
    scope: 'openid profile email',
    state,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256'
  });

  res.redirect(`https://provider.com/authorize?${params}`);
});

// Step 2: Handle callback
app.get('/auth/callback', async (req, res) => {
  // Verify state (CSRF protection)
  if (req.query.state !== req.session.oauthState) {
    return res.status(403).send('Invalid state');
  }

  const response = await fetch('https://provider.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code: req.query.code,
      code_verifier: req.session.codeVerifier,
      client_id: process.env.OAUTH_CLIENT_ID,
      redirect_uri: 'https://myapp.com/auth/callback'
    })
  });

  const tokens = await response.json();
  // Verify ID token, create session
});
```

---

## API Key Security

```javascript
const crypto = require('crypto');

// Generate: prefix + random bytes
function generateApiKey() {
  return `sk_live_${crypto.randomBytes(32).toString('hex')}`;
}

// Store: hash only, never plaintext
function hashApiKey(key) {
  return crypto.createHash('sha256').update(key).digest('hex');
}

// Verify middleware
async function apiKeyAuth(req, res, next) {
  const key = req.headers.authorization?.replace('Bearer ', '');
  if (!key) return res.status(401).json({ error: 'Missing API key' });

  const hash = hashApiKey(key);
  const record = await db.apiKeys.findOne({ hash });
  if (!record) return res.status(401).json({ error: 'Invalid API key' });

  req.userId = record.userId;
  next();
}
```

---

## Rate Limiting

```javascript
const rateLimit = require('express-rate-limit');

// General API limiter
app.use('/api/', rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false
}));

// Strict auth limiter
app.use('/auth/login', rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  skipSuccessfulRequests: true,
  message: { error: 'Too many login attempts, try again later' }
}));

// Tiered limiting
app.use('/api/v1/', rateLimit({
  windowMs: 60 * 1000,
  max: (req) => {
    if (req.user?.tier === 'premium') return 1000;
    if (req.user?.tier === 'pro') return 500;
    return 100;
  }
}));
```

---

## Secrets Management

### Environment Variables
```javascript
require('dotenv').config();

// Validate required secrets at startup
const REQUIRED = ['JWT_SECRET', 'DB_PASSWORD', 'OAUTH_CLIENT_SECRET'];
for (const key of REQUIRED) {
  if (!process.env[key]) {
    console.error(`Missing required env var: ${key}`);
    process.exit(1);
  }
}

// Never log secrets
function sanitizeForLogging(env) {
  const sensitive = ['PASSWORD', 'SECRET', 'KEY', 'TOKEN'];
  return Object.fromEntries(
    Object.entries(env).map(([k, v]) => [
      k, sensitive.some(s => k.includes(s)) ? '[REDACTED]' : v
    ])
  );
}
```

### .env Security
```bash
# .env.example (committed — no real values)
DB_PASSWORD=CHANGE_ME
JWT_SECRET=CHANGE_ME

# .env (gitignored — real values)
DB_PASSWORD=actual-secret
JWT_SECRET=actual-secret
```

**.gitignore must contain:**
```
.env
.env.local
.env.*.local
*.pem
*.key
```

---

## Cryptography Essentials

### Secure Random Generation
```javascript
const crypto = require('crypto');

// Session tokens, CSRF tokens, API keys
const token = crypto.randomBytes(32).toString('hex');

// Numeric codes (OTP, verification)
const code = crypto.randomInt(100000, 999999).toString();

// NEVER use Math.random() for security purposes
```

### AES-256-GCM Encryption
```javascript
const ALGO = 'aes-256-gcm';

function encrypt(plaintext, key) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGO, key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, encrypted]).toString('base64');
}

function decrypt(ciphertext, key) {
  const buf = Buffer.from(ciphertext, 'base64');
  const iv = buf.subarray(0, 16);
  const tag = buf.subarray(16, 32);
  const encrypted = buf.subarray(32);
  const decipher = crypto.createDecipheriv(ALGO, key, iv);
  decipher.setAuthTag(tag);
  return decipher.update(encrypted, undefined, 'utf8') + decipher.final('utf8');
}
```

### Crypto Rules
- **Passwords**: Argon2id (preferred) or bcrypt (minimum rounds: 12)
- **Encryption**: AES-256-GCM (authenticated encryption)
- **Hashing**: SHA-256 for integrity, HMAC-SHA256 for signatures
- **Randomness**: Always `crypto.randomBytes()`, never `Math.random()`
- **Key derivation**: `crypto.scryptSync()` or HKDF
- **Never**: Roll your own crypto, use ECB mode, use MD5/SHA1 for security



---

## Reference file: `database-and-deps.md`

# Database & Dependency Security Reference

## SQL Injection Prevention

### Parameterized Queries (Every Database)

```javascript
// PostgreSQL (pg)
const { rows } = await pool.query(
  'SELECT * FROM users WHERE email = $1 AND org_id = $2',
  [email, orgId]
);

// MySQL (mysql2)
const [rows] = await connection.execute(
  'SELECT * FROM users WHERE email = ? AND org_id = ?',
  [email, orgId]
);

// SQLite (better-sqlite3)
const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
```

### ORM Security

```javascript
// Prisma — safe by default
const user = await prisma.user.findUnique({ where: { id: userId } });
const users = await prisma.user.findMany({
  where: { name: { contains: searchTerm } } // Auto-parameterized
});

// DANGER: Raw queries bypass ORM protection
// Only use when necessary, ALWAYS parameterize
const result = await prisma.$queryRaw`
  SELECT * FROM users WHERE id = ${userId}
`; // Tagged template — Prisma parameterizes this

// WRONG — string concatenation in raw query
// await prisma.$queryRawUnsafe(`SELECT * FROM users WHERE id = ${userId}`);
```

```javascript
// Knex — query builder (safe)
const users = await knex('users')
  .where('email', email)
  .andWhere('status', 'active')
  .select('id', 'name', 'email');

// Knex — raw (parameterize manually)
const users = await knex.raw('SELECT * FROM users WHERE id = ?', [userId]);
```

```javascript
// TypeORM
const user = await userRepo.findOne({ where: { id: userId } });

// TypeORM — QueryBuilder (safe)
const users = await userRepo
  .createQueryBuilder('user')
  .where('user.email = :email', { email })
  .getMany();
```

### MongoDB Injection Prevention

```javascript
// Mongoose — safe with schema validation
const user = await User.findById(userId); // ObjectId validated

// DANGER: $where and $regex with user input
// WRONG:
// await User.find({ $where: `this.name == '${name}'` });

// CORRECT: Use structured queries
await User.find({ name: { $eq: name } });

// Sanitize query operators — block $ prefix in user input
function sanitizeMongoInput(input) {
  if (typeof input === 'object' && input !== null) {
    for (const key of Object.keys(input)) {
      if (key.startsWith('$')) delete input[key];
    }
  }
  return input;
}
```

---

## Connection Security

### Encrypted Connections
```javascript
// PostgreSQL with SSL
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: {
    rejectUnauthorized: true, // Verify server certificate
    ca: fs.readFileSync('/path/to/ca-cert.pem')
  },
  max: 20
});

// MySQL with SSL
const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: { rejectUnauthorized: true }
});
```

### Connection String Security
```javascript
// NEVER hardcode credentials
// WRONG: const db = connect('postgres://admin:password@host/db');

// Use env vars
const db = connect(process.env.DATABASE_URL);

// Validate at startup
if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL not set');
  process.exit(1);
}
```

### Connection Pool Limits
```javascript
const pool = new Pool({
  max: 20,                          // Max connections
  idleTimeoutMillis: 30000,         // Close idle connections after 30s
  connectionTimeoutMillis: 5000,    // Fail fast if can't connect
  allowExitOnIdle: true
});

// Always release connections
const client = await pool.connect();
try {
  const result = await client.query('SELECT * FROM users WHERE id = $1', [id]);
  return result.rows;
} finally {
  client.release(); // ALWAYS release, even on error
}
```

---

## Field-Level Encryption

```javascript
const crypto = require('crypto');

// Encrypt sensitive columns before storage
class FieldEncryption {
  constructor(masterKey) {
    this.key = crypto.scryptSync(masterKey, 'field-encrypt-salt', 32);
  }

  encrypt(value) {
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv('aes-256-gcm', this.key, iv);
    const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return Buffer.concat([iv, tag, encrypted]).toString('base64');
  }

  decrypt(ciphertext) {
    const buf = Buffer.from(ciphertext, 'base64');
    const iv = buf.subarray(0, 16);
    const tag = buf.subarray(16, 32);
    const data = buf.subarray(32);
    const decipher = crypto.createDecipheriv('aes-256-gcm', this.key, iv);
    decipher.setAuthTag(tag);
    return decipher.update(data, undefined, 'utf8') + decipher.final('utf8');
  }
}

// Usage with ORM
const fieldCrypto = new FieldEncryption(process.env.FIELD_ENCRYPTION_KEY);

// Before save
user.ssn = fieldCrypto.encrypt(plainSSN);
await user.save();

// After read
const plainSSN = fieldCrypto.decrypt(user.ssn);
```

---

## Dependency Supply Chain Security

### Lock Files — Always Commit
```bash
# These MUST be in version control
package-lock.json    # npm
yarn.lock           # yarn
pnpm-lock.yaml      # pnpm
Cargo.lock          # Rust

# CI: Use lockfile-only installs
npm ci              # NOT npm install
yarn --frozen-lockfile
pnpm install --frozen-lockfile
```

### Dependency Auditing
```bash
# Run regularly (weekly minimum, on every CI build ideally)
npm audit
npm audit fix --audit-level=high

# More comprehensive tools
npx snyk test
npx retire

# Check for known malicious packages
npx npm-check-updates --upgrade
```

### Version Pinning Strategy
```json
{
  "dependencies": {
    "express": "4.18.2",       // Exact pin for critical deps
    "cors": "^2.8.5",          // Minor/patch for trusted deps
    "lodash": "~4.17.21"       // Patch only for stable deps
  }
}
```

**Rules:**
- Pin exact versions for security-critical packages (auth, crypto, DB drivers)
- Use `^` for well-maintained packages you trust
- Never use `*` or `latest`
- Review changelogs before major version bumps

### Subresource Integrity (SRI) for CDN

```html
<!-- Always use SRI for CDN-loaded scripts -->
<script
  src="https://cdn.example.com/lib.js"
  integrity="sha384-oqVuAfXRKap7fdgcCY5..."
  crossorigin="anonymous"
></script>

<!-- Generate SRI hash -->
<!-- openssl dgst -sha384 -binary lib.js | openssl base64 -A -->
```

### .gitignore Security Essentials
```
# Secrets — never commit
.env
.env.local
.env.*.local
*.pem
*.key
*.p12
credentials.json
service-account.json

# Dependencies — don't commit
node_modules/
vendor/

# Build artifacts
.trigger/
dist/
build/
```

### Supply Chain Attack Prevention
- Review new dependencies before adding (check maintainers, download count, last update)
- Use `npm audit signatures` to verify package provenance
- Enable 2FA on your npm account
- Use scoped packages for internal code (@myorg/package)
- Monitor for typosquatting (lodash vs l0dash)
- Consider using a private registry for critical projects
- Set up Dependabot or Renovate for automated security updates

---

## Database Security Checklist

- [ ] All queries use parameterized statements or ORM
- [ ] No raw SQL with string concatenation
- [ ] Database connections use SSL/TLS
- [ ] Connection strings from env vars, not hardcoded
- [ ] Connection pool limits configured
- [ ] Connections always released (try/finally pattern)
- [ ] Sensitive fields encrypted at rest
- [ ] Database user has minimum required privileges
- [ ] No default/weak database passwords
- [ ] Regular backups with encryption
- [ ] Audit logging for sensitive operations



---

## Reference file: `desktop-security.md`

# Desktop Application Security Reference

## Electron Security

### Secure Window Configuration
```javascript
const win = new BrowserWindow({
  webPreferences: {
    contextIsolation: true,        // Separate JS contexts (MANDATORY)
    nodeIntegration: false,         // No Node.js in renderer (MANDATORY)
    sandbox: true,                  // OS-level sandboxing (MANDATORY)
    webSecurity: true,              // Same-origin policy (MANDATORY)
    enableRemoteModule: false,      // Deprecated, dangerous
    preload: path.join(__dirname, 'preload.js'),
    allowRunningInsecureContent: false
  }
});
```

**What happens without these:**
- `nodeIntegration: true` → XSS becomes RCE (`require('child_process').exec()`)
- `contextIsolation: false` → Renderer can tamper with preload globals
- `sandbox: false` → Renderer has broader OS access
- `webSecurity: false` → Same-origin policy disabled, data theft possible

### Preload Script — Minimal API Surface

```javascript
// preload.js — expose ONLY specific, validated functions
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  loadPreferences: () => ipcRenderer.invoke('prefs:load'),
  savePreferences: (prefs) => {
    if (!prefs || typeof prefs !== 'object') throw new Error('Invalid prefs');
    return ipcRenderer.invoke('prefs:save', prefs);
  },
  openExternal: (url) => {
    if (typeof url !== 'string') throw new Error('Invalid URL');
    return ipcRenderer.invoke('shell:open-external', url);
  }
  // NEVER expose: ipcRenderer directly, require(), process, fs
});
```

### IPC Security — Validate Everything

```javascript
// main.js
const { ipcMain, shell } = require('electron');

ipcMain.handle('prefs:load', async (event) => {
  // Validate sender
  if (event.sender !== mainWindow.webContents) {
    throw new Error('Unauthorized sender');
  }
  return loadPreferences();
});

ipcMain.handle('prefs:save', async (event, prefs) => {
  if (event.sender !== mainWindow.webContents) throw new Error('Unauthorized');

  // Schema validation
  if (!prefs || typeof prefs !== 'object') throw new Error('Invalid data');
  if (typeof prefs.theme !== 'string') throw new Error('Invalid theme');

  return savePreferences(prefs);
});

ipcMain.handle('shell:open-external', async (event, url) => {
  if (event.sender !== mainWindow.webContents) throw new Error('Unauthorized');

  // URL validation — only allow HTTPS
  try {
    const parsed = new URL(url);
    if (!['https:', 'http:'].includes(parsed.protocol)) {
      throw new Error('Invalid protocol');
    }
  } catch { throw new Error('Invalid URL'); }

  return shell.openExternal(url);
});
```

### CSP for Electron

```javascript
// Set via webRequest (works with file:// protocol)
session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
  callback({
    responseHeaders: {
      ...details.responseHeaders,
      'Content-Security-Policy': [
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://api.myapp.com"
      ]
    }
  });
});
```

### Deep Link Security

```javascript
app.setAsDefaultProtocolClient('myapp');

app.on('open-url', (event, url) => {
  event.preventDefault();

  try {
    const parsed = new URL(url);

    // Validate protocol
    if (parsed.protocol !== 'myapp:') return;

    // Allowlist valid hosts
    const allowedHosts = ['auth', 'open', 'settings'];
    if (!allowedHosts.includes(parsed.hostname)) return;

    // Length limit
    if (url.length > 2000) return;

    // Sanitize params
    for (const [, value] of parsed.searchParams) {
      if (/[<>"'`;]/.test(value)) return; // Block injection chars
    }

    handleDeepLink(parsed);
  } catch {
    // Invalid URL — silently ignore
  }
});
```

### Auto-Updater Security

```javascript
const { autoUpdater } = require('electron-updater');

// Always HTTPS, always signed
autoUpdater.on('update-downloaded', async (info) => {
  const { response } = await dialog.showMessageBox(mainWindow, {
    type: 'info',
    buttons: ['Restart Now', 'Later'],
    message: `Update ${info.version} ready`
  });
  if (response === 0) autoUpdater.quitAndInstall();
});

autoUpdater.on('error', (err) => {
  // Never silently fail — don't install unverified updates
  console.error('Update failed:', err.message);
});

// Check after app is ready (not on startup — slows launch)
setTimeout(() => autoUpdater.checkForUpdates(), 30000);
```

### Credential Storage

```javascript
const { safeStorage } = require('electron');

function storeSecret(key, value) {
  if (!safeStorage.isEncryptionAvailable()) {
    throw new Error('Encryption not available');
  }
  const encrypted = safeStorage.encryptString(value);
  store.set(key, encrypted.toString('base64'));
}

function retrieveSecret(key) {
  const encrypted = Buffer.from(store.get(key), 'base64');
  return safeStorage.decryptString(encrypted);
}
```

### WebView / BrowserView / iframe

**Preference order (most to least secure):**
1. **iframe with sandbox** — best isolation for web content
2. **BrowserView** — Chromium-level isolation
3. **WebView tag** — deprecated, avoid

```javascript
// BrowserView with full security
const view = new BrowserView({
  webPreferences: {
    sandbox: true,
    contextIsolation: true,
    nodeIntegration: false
  }
});
```

### Electron Vulnerability Checklist
- [ ] `contextIsolation: true`
- [ ] `nodeIntegration: false`
- [ ] `sandbox: true`
- [ ] `webSecurity: true`
- [ ] No `remote` module usage
- [ ] Preload uses `contextBridge` with minimal API
- [ ] IPC validates sender AND message schema
- [ ] Deep links validated against allowlist
- [ ] Auto-updater uses HTTPS + code signing
- [ ] CSP headers configured
- [ ] No `eval()` or `Function()` in renderer
- [ ] Credentials stored via `safeStorage`

---

## Tauri Security

### Command Security

```rust
// Define commands with strict typing — Rust enforces at compile time
#[tauri::command]
async fn read_user_data(user_id: u32) -> Result<UserData, String> {
    if user_id == 0 {
        return Err("Invalid user ID".to_string());
    }
    db::get_user(user_id).map_err(|e| e.to_string())
}

// Register only needed commands
tauri::Builder::default()
    .invoke_handler(tauri::generate_handler![read_user_data])
    .run(tauri::generate_context!())
    .expect("error running app");
```

### Scope Configuration (tauri.conf.json)

```json
{
  "app": {
    "security": {
      "csp": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
    }
  },
  "plugins": {
    "fs": {
      "scope": [{ "path": "$APPDATA/**", "allow": ["read", "write"] }]
    },
    "http": {
      "scope": [
        { "allow": ["https://api.myapp.com/**"] },
        { "deny": ["https://api.myapp.com/admin/**"] }
      ]
    },
    "shell": {
      "scope": [{ "name": "open", "allow": ["open"] }]
    }
  }
}
```

### Per-Window Capabilities

```json
{
  "security": {
    "capabilities": [
      {
        "windows": ["main"],
        "permissions": ["core:default", "fs:allow-read:$APPDATA"]
      },
      {
        "windows": ["settings"],
        "permissions": ["core:default", "fs:allow-read:$APPCONFIG"]
      },
      {
        "windows": ["untrusted"],
        "permissions": []
      }
    ]
  }
}
```

### Tauri Security Rules
- Use `invoke()` for sensitive operations (not events)
- Define restrictive scopes — deny by default
- Validate all command inputs even though Rust types help
- Configure CSP in tauri.conf.json
- Use per-window capabilities (least privilege)
- Audit third-party plugins before adding
- Code-sign all builds for distribution

### Tauri Vulnerability Checklist
- [ ] Commands validate all inputs
- [ ] File system scopes are restrictive
- [ ] HTTP scopes whitelist specific endpoints
- [ ] Shell scopes limit allowed commands
- [ ] CSP configured
- [ ] Per-window capabilities defined
- [ ] Plugins from trusted sources only
- [ ] Credentials in OS keychain (not plaintext files)
- [ ] Code signed for distribution
- [ ] Updates over HTTPS with signature verification

---

## Common Desktop Security Patterns

### Code Signing
- **Windows**: EV certificate (SmartScreen trusted) via Azure Key Vault
- **macOS**: Developer ID certificate + notarization
- **Linux**: GPG signing for packages
- **Never**: Commit private keys to version control

### Secure Auto-Update Flow
1. Check for updates over HTTPS only
2. Verify code signature of downloaded update
3. Verify checksum matches manifest
4. Ask user before installing (don't auto-install silently)
5. Fall back gracefully on verification failure

### Sandboxing Strategy
- Renderer processes: Always sandboxed
- Main process: Minimize direct OS access
- File access: Through validated IPC only
- Network access: Scoped to known endpoints
- Privileges: Minimum required per window/component



---

## Reference file: `web-security.md`

# Web Security Reference

## XSS (Cross-Site Scripting) Prevention

### Output Escaping by Context

**HTML context** — escape `& < > " '`:
```javascript
const escapeHtml = (text) => {
  const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' };
  return text.replace(/[&<>"']/g, m => map[m]);
};
```

**React/Vue/Svelte** — auto-escape by default. Dangerous exceptions:
```jsx
// React: dangerouslySetInnerHTML — sanitize first
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(html) }} />

// Vue: v-html — sanitize first
<div v-html="DOMPurify.sanitize(userContent)" />

// Svelte: {@html} — sanitize first
{@html DOMPurify.sanitize(html)}
```

**URL context** — validate protocol:
```javascript
function safeHref(url) {
  try {
    const parsed = new URL(url);
    return ['http:', 'https:', 'mailto:'].includes(parsed.protocol) ? url : '#';
  } catch { return '#'; }
}
```

### Content Security Policy (CSP)

```javascript
// Express + Helmet
const helmet = require('helmet');
app.use((req, res, next) => {
  res.locals.nonce = crypto.randomBytes(16).toString('hex');
  next();
});

app.use(helmet.contentSecurityPolicy({
  directives: {
    defaultSrc: ["'self'"],
    scriptSrc: ["'self'", (req, res) => `'nonce-${res.locals.nonce}'`],
    styleSrc: ["'self'", (req, res) => `'nonce-${res.locals.nonce}'`],
    imgSrc: ["'self'", 'data:', 'https:'],
    connectSrc: ["'self'"],
    frameSrc: ["'none'"],
    objectSrc: ["'none'"],
    upgradeInsecureRequests: []
  }
}));
```

**Never use:** `'unsafe-inline'`, `'unsafe-eval'`, or wildcard `*` for script-src.

---

## CSRF Prevention

### SameSite Cookies (primary defense)
```javascript
res.cookie('session', token, {
  httpOnly: true,
  secure: true,
  sameSite: 'Strict', // or 'Lax' for links from external sites
  maxAge: 3600000,
  path: '/'
});
```

### CSRF Tokens (defense in depth)
```javascript
const csrf = require('csurf');
app.use(csrf({ cookie: false })); // session-based, not cookie-based

// Include in forms
app.get('/form', (req, res) => {
  res.render('form', { csrfToken: req.csrfToken() });
});

// AJAX: send via header
fetch('/api/action', {
  method: 'POST',
  headers: { 'X-CSRF-Token': csrfToken },
  body: JSON.stringify(data)
});
```

---

## Injection Prevention

### SQL — Always Parameterize
```javascript
// Raw SQL — parameterized
db.query('SELECT * FROM users WHERE id = ? AND status = ?', [userId, status]);

// Knex query builder
const user = await knex('users').where({ id: userId }).first();

// Prisma ORM
const user = await prisma.user.findUnique({ where: { id: userId } });
```

### Command — Never Concatenate
```javascript
// WRONG: exec() parses through shell
exec(`convert ${userFile} output.png`); // command injection!

// CORRECT: spawn() with array args, no shell parsing
spawn('convert', [userFile, 'output.png']);

// CORRECT: execFile() — no shell
execFile('convert', [userFile, 'output.png']);
```

### Path Traversal — Resolve and Verify
```javascript
const path = require('path');
const UPLOADS_DIR = path.resolve('./uploads');

function safePath(userInput) {
  const resolved = path.resolve(UPLOADS_DIR, userInput);
  if (!resolved.startsWith(UPLOADS_DIR + path.sep) && resolved !== UPLOADS_DIR) {
    throw new Error('Path traversal blocked');
  }
  return resolved;
}
```

---

## SSRF Prevention

```javascript
function validateUrl(urlString) {
  const parsed = new URL(urlString);

  // HTTPS only
  if (parsed.protocol !== 'https:') return false;

  // Block private/internal IPs
  const blocked = ['localhost', '127.0.0.1', '0.0.0.0', '169.254', '10.', '172.16', '192.168', '[::1]'];
  if (blocked.some(b => parsed.hostname.startsWith(b) || parsed.hostname === b)) return false;

  // Allowlist approach (preferred)
  const allowed = ['api.example.com', 'cdn.example.com'];
  if (!allowed.includes(parsed.hostname)) return false;

  return true;
}
```

---

## Input Validation

### Schema Validation (Zod example)
```typescript
import { z } from 'zod';

const CreateUserSchema = z.object({
  email: z.string().email().max(255),
  name: z.string().min(1).max(100).trim(),
  age: z.number().int().min(0).max(150),
  role: z.enum(['user', 'admin']),
});

// In route handler
app.post('/users', (req, res) => {
  const result = CreateUserSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(400).json({ error: result.error.flatten() });
  }
  // result.data is typed and validated
});
```

### File Upload Validation
```javascript
const multer = require('multer');
const upload = multer({
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB max
  fileFilter: (req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (!allowed.includes(file.mimetype)) {
      return cb(new Error('Invalid file type'));
    }
    cb(null, true);
  }
});

// Don't trust file extension — verify magic bytes
import { fileTypeFromBuffer } from 'file-type';

async function validateFile(buffer) {
  const type = await fileTypeFromBuffer(buffer);
  if (!type || !['image/jpeg', 'image/png', 'image/webp'].includes(type.mime)) {
    throw new Error('Invalid file type');
  }
}
```

---

## Security Headers

### Complete Header Set
```javascript
app.use(helmet()); // Sets most headers with sane defaults

// Additional manual headers
app.use((req, res, next) => {
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'geolocation=(), camera=(), microphone=()');
  next();
});

app.disable('x-powered-by');
```

### Header Reference

| Header | Value | Purpose |
|--------|-------|---------|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains; preload` | Force HTTPS |
| `X-Content-Type-Options` | `nosniff` | Block MIME sniffing |
| `X-Frame-Options` | `DENY` | Prevent clickjacking |
| `Content-Security-Policy` | `default-src 'self'; script-src 'nonce-{N}'` | XSS prevention |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Limit referrer leakage |
| `Permissions-Policy` | `geolocation=(), camera=()` | Restrict browser features |

---

## CORS Configuration

```javascript
const cors = require('cors');

// WRONG: Allow everything
// app.use(cors()); // Allows all origins!

// CORRECT: Explicit allowlist
app.use(cors({
  origin: ['https://myapp.com', 'https://admin.myapp.com'],
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
  maxAge: 86400
}));
```

---

## iframe Security

```html
<!-- Restrictive sandbox for untrusted content -->
<iframe
  src="https://trusted.com/embed"
  sandbox="allow-scripts allow-same-origin"
  allow="geolocation 'none'; camera 'none'; microphone 'none'"
  referrerpolicy="no-referrer"
></iframe>
```

**postMessage validation:**
```javascript
window.addEventListener('message', (event) => {
  if (event.origin !== 'https://trusted.com') return; // Verify origin!
  // Process event.data
});
```

