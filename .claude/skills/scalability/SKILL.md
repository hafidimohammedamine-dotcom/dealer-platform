---
name: "scalability"
description: "Design and build scalable software systems. Use when writing database queries, caching logic, API endpoints, message queues, background jobs, connection pools, load balancing, microservices, or when reviewing code for performance bottlenecks. Covers database scaling, caching strategies, async processing, API design for scale, concurrency, frontend performance, observability, and infrastructure patterns."
---

# Software Scalability

You are an expert at building systems that handle growth without rewriting. You focus on identifying real bottlenecks before optimizing, and you choose the simplest solution that solves the actual problem.

Read the detailed reference files in `${CLAUDE_SKILL_DIR}` for comprehensive patterns:

- `database-scaling.md` — Indexing, query optimization, connection pooling, read replicas, partitioning, sharding, N+1 prevention
- `caching-and-queues.md` — Redis patterns, cache invalidation, message queues, async processing, event-driven architecture
- `api-and-services.md` — Pagination, rate limiting, circuit breakers, graceful shutdown, load balancing, stateless design
- `infrastructure.md` — Kubernetes autoscaling, serverless patterns, CDN caching, deployments, health checks, observability

## The Scalability Mindset

**Rule #1: Don't optimize what you haven't measured.** Profile first, then fix the actual bottleneck.

### Bottleneck Identification Flow

```
Slow response times?
  ↓
Where is time spent?
  ├─ Database (>50% of request time) → See database-scaling.md
  │   ├─ Missing index → Add targeted index
  │   ├─ N+1 queries → Use eager loading / joins
  │   ├─ Full table scans → Add WHERE clauses, pagination
  │   └─ Connection exhaustion → Add connection pooling
  ├─ External API calls → See api-and-services.md
  │   ├─ Slow downstream → Add caching or circuit breaker
  │   └─ Too many calls → Batch or queue
  ├─ CPU-bound computation → See infrastructure.md
  │   ├─ Can parallelize → Worker threads / cluster mode
  │   └─ Can defer → Move to background queue
  └─ Memory pressure → Profile allocations
      ├─ Large payloads → Stream instead of buffer
      └─ Memory leaks → Heap snapshot analysis
```

## Quick Wins — The 80/20 of Scaling

These solve most scaling problems before you need anything complex:

### 1. Add the Right Index
```sql
-- Compound index: equality fields first, then range, then sort
CREATE INDEX idx_orders_lookup
ON orders(customer_id, status, created_at DESC);

-- Partial index: index only what you query
CREATE INDEX idx_active_users
ON users(email) WHERE status = 'active';
```

### 2. Fix N+1 Queries
```typescript
// BAD: 1 + N queries
const users = await prisma.user.findMany();
for (const u of users) u.posts = await prisma.post.findMany({ where: { authorId: u.id } });

// GOOD: 2 queries total
const users = await prisma.user.findMany({ include: { posts: true } });
```

### 3. Add Caching Where It Matters
```typescript
async function getUser(id: string) {
  const cached = await redis.get(`user:${id}`);
  if (cached) return JSON.parse(cached);

  const user = await db.user.findUnique({ where: { id } });
  await redis.setex(`user:${id}`, 300, JSON.stringify(user)); // 5min TTL
  return user;
}
```

### 4. Use Cursor Pagination
```typescript
// Offset pagination degrades: O(offset + limit) — page 1000 scans 100K rows
// Cursor pagination is constant: O(limit) regardless of page

const results = await prisma.post.findMany({
  take: 20,
  cursor: lastId ? { id: lastId } : undefined,
  skip: lastId ? 1 : 0,
  orderBy: { id: 'asc' }
});
```

### 5. Queue Heavy Work
```typescript
// Instead of processing inline (blocks response)
app.post('/upload', async (req, res) => {
  await queue.add('process-upload', { fileId: req.body.fileId });
  res.json({ status: 'queued' }); // Respond immediately
});
```

### 6. Connection Pooling
```
Pool size = (CPU cores × 2) + 1
4 cores → 9 connections
8 cores → 17 connections
```

## Scaling Decision Matrix

| Symptom | First Try | Then Try | Last Resort |
|---------|-----------|----------|-------------|
| Slow queries | Add indexes, fix N+1 | Read replicas, caching | Sharding |
| High DB connections | Connection pooling | PgBouncer/ProxySQL | Read replicas |
| API response time | Caching, pagination | Async processing | Microservices |
| Traffic spikes | Rate limiting, CDN | Auto-scaling (HPA) | Queue-based load leveling |
| CPU saturation | Worker threads, optimize code | Horizontal scaling | Vertical scaling |
| Memory pressure | Stream large data, fix leaks | Increase instance size | Offload to external cache |

## Thresholds — When to Act

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| p99 latency | < 200ms | 200-500ms | > 500ms |
| DB cache hit ratio | > 99% | 95-99% | < 95% |
| DB connection utilization | < 60% | 60-80% | > 80% |
| CPU utilization | < 50% | 50-70% | > 70% |
| Memory utilization | < 60% | 60-80% | > 80% |
| Error rate | < 0.1% | 0.1-1% | > 1% |
| Queue depth | Stable | Growing | Growing fast |
| Read:write ratio | N/A | > 10:1 consider replicas | > 50:1 must have replicas |

## Critical Rules

1. **Measure before optimizing** — Use EXPLAIN ANALYZE, profilers, APM tools; gut feelings are wrong
2. **Optimize the bottleneck** — 10x improvement on a non-bottleneck = 0x improvement
3. **Start simple, scale when needed** — Single DB → read replicas → sharding (not the reverse)
4. **Cache reads, queue writes** — Reads are cheap to cache; writes benefit from async processing
5. **Stateless by default** — Session state in Redis/DB, not in memory; enables horizontal scaling
6. **Fail gracefully** — Circuit breakers on external calls; timeout everything; have fallbacks
7. **Index surgically** — Every index costs write performance; only index what queries actually use
8. **Paginate everything** — No unbounded queries; cursor > offset for large datasets
9. **Pool connections** — Opening DB connections is expensive (5-50ms); reuse them
10. **Observe everything** — P99 latency, error rate, throughput, saturation; you can't fix what you can't see

Use `$ARGUMENTS` to focus on a specific scaling area. Read the relevant reference file before writing code.


# Appendix: Bundled Reference Files


---

## Reference file: `api-and-services.md`

# API Design & Service Resilience Reference

## Pagination

### Cursor-Based (Recommended for Scale)
```typescript
// Constant performance regardless of page depth
app.get('/posts', async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100); // Max 100
  const cursor = req.query.cursor;

  const posts = await prisma.post.findMany({
    take: limit + 1, // Fetch 1 extra to detect hasMore
    ...(cursor && { cursor: { id: cursor }, skip: 1 }),
    orderBy: { id: 'asc' }
  });

  const hasMore = posts.length > limit;
  const data = hasMore ? posts.slice(0, -1) : posts;

  res.json({
    data,
    pagination: {
      hasMore,
      nextCursor: hasMore ? data[data.length - 1].id : null
    }
  });
});
```

### Offset-Based (Simple, Limited Scale)
```typescript
// Performance degrades at high offsets (DB scans offset + limit rows)
app.get('/posts', async (req, res) => {
  const page = Math.max(parseInt(req.query.page) || 1, 1);
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);
  const offset = (page - 1) * limit;

  // DANGER: offset=100000 scans 100K rows to skip them
  if (offset > 10000) return res.status(400).json({ error: 'Use cursor pagination for deep pages' });

  const [data, total] = await Promise.all([
    prisma.post.findMany({ skip: offset, take: limit, orderBy: { id: 'asc' } }),
    prisma.post.count()
  ]);

  res.json({ data, pagination: { page, limit, total, totalPages: Math.ceil(total / limit) } });
});
```

**Rule:** Use cursor for APIs consumed by infinite scroll or programmatic clients. Use offset only for admin UIs where page numbers matter and data is small.

---

## Rate Limiting

### Tiered Rate Limiting
```typescript
import rateLimit from 'express-rate-limit';

// Global: 100 req/15min per IP
app.use('/api/', rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false
}));

// Auth: 5 attempts/15min (strict)
app.use('/auth/', rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  skipSuccessfulRequests: true
}));

// Per-tier limiting
app.use('/api/v1/', rateLimit({
  windowMs: 60 * 1000,
  max: (req) => {
    if (req.user?.tier === 'enterprise') return 5000;
    if (req.user?.tier === 'pro') return 1000;
    return 100;
  }
}));
```

### Response Headers
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 42
X-RateLimit-Reset: 1700000000
Retry-After: 30
```

---

## Circuit Breaker

### Implementation (Opossum)
```typescript
import CircuitBreaker from 'opossum';

const paymentBreaker = new CircuitBreaker(
  async (userId: string, amount: number) => {
    return await paymentService.charge(userId, amount);
  },
  {
    timeout: 3000,                  // 3s timeout per call
    errorThresholdPercentage: 50,   // Open at 50% failure
    resetTimeout: 30000,            // Try again after 30s
    volumeThreshold: 10             // Min requests before calculating %
  }
);

// Fallback when circuit is open
paymentBreaker.fallback(() => ({ status: 'degraded', message: 'Payments temporarily unavailable' }));

// Use it
const result = await paymentBreaker.fire(userId, 99.99);

// Monitor
paymentBreaker.on('open', () => logger.error('Payment circuit OPEN'));
paymentBreaker.on('halfOpen', () => logger.warn('Payment circuit testing...'));
paymentBreaker.on('close', () => logger.info('Payment circuit recovered'));
```

### Circuit Breaker States
```
CLOSED ──(failures > threshold)──→ OPEN ──(resetTimeout)──→ HALF-OPEN
  ↑                                                             │
  └──────────(success)──────────────────────────────────────────┘
  └──────────────────────────────────(failure)──→ OPEN
```

### Configuration Guidelines
- `timeout`: Set to p99 latency + 20% buffer
- `errorThresholdPercentage`: 50% for aggressive, 25% for conservative
- `resetTimeout`: 30-60s (match service recovery time)
- `volumeThreshold`: 10-20 (avoid opening on 1 failure)

---

## Graceful Shutdown

```typescript
const server = http.createServer(app);
let shuttingDown = false;

process.on('SIGTERM', async () => {
  console.log('SIGTERM received, draining...');
  shuttingDown = true;

  // 1. Stop accepting new connections
  server.close(async () => {
    // 2. Close DB, cache, queue connections
    await Promise.allSettled([
      prisma.$disconnect(),
      redis.quit(),
      worker.close()
    ]);
    process.exit(0);
  });

  // 3. Force exit after 30s if still draining
  setTimeout(() => {
    console.error('Forced shutdown after timeout');
    process.exit(1);
  }, 30000);
});

// Reject new requests during shutdown
app.use((req, res, next) => {
  if (shuttingDown) return res.status(503).json({ error: 'Shutting down' });
  next();
});
```

---

## Load Balancing

### Strategy Selection

| Strategy | Use When |
|----------|----------|
| **Round Robin** | All instances are equal, stateless |
| **Least Connections** | Instances have varying capacity |
| **Consistent Hashing** | Need session affinity or cache locality |
| **Weighted** | Mixed instance sizes |

### Health Checks (Kubernetes)
```yaml
# Startup: Is the app initialized?
startupProbe:
  httpGet: { path: /startup, port: 8080 }
  periodSeconds: 10
  failureThreshold: 30    # 5 min max startup

# Readiness: Can it handle traffic?
readinessProbe:
  httpGet: { path: /ready, port: 8080 }
  periodSeconds: 10
  failureThreshold: 3     # Remove after 3 failures

# Liveness: Is it alive? (restart if not)
livenessProbe:
  httpGet: { path: /health, port: 8080 }
  periodSeconds: 20
  failureThreshold: 3
```

```typescript
app.get('/ready', async (req, res) => {
  const dbOk = await prisma.$queryRaw`SELECT 1`.then(() => true).catch(() => false);
  const redisOk = await redis.ping().then(() => true).catch(() => false);
  const ready = dbOk && redisOk && !shuttingDown;
  res.status(ready ? 200 : 503).json({ ready, db: dbOk, redis: redisOk });
});

app.get('/health', (req, res) => res.json({ alive: true }));
```

---

## Stateless Design

### Session Externalization
```typescript
// WRONG: In-memory sessions (breaks with multiple instances)
const sessions = new Map();

// CORRECT: Redis-backed sessions
import session from 'express-session';
import RedisStore from 'connect-redis';

app.use(session({
  store: new RedisStore({ client: redis }),
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: { secure: true, httpOnly: true, maxAge: 3600000 }
}));
```

### Stateless Auth (JWT)
```typescript
// No server-side state needed — token carries identity
const token = jwt.sign({ sub: userId, role: 'user' }, secret, { expiresIn: '15m' });

// Any instance can verify without shared state
const user = jwt.verify(token, secret);
```

**JWT vs Redis Sessions:**
| Factor | JWT | Redis Sessions |
|--------|-----|----------------|
| Revocation | Hard (wait for expiry) | Instant (delete key) |
| Scalability | Excellent (no state) | Good (Redis cluster) |
| Token size | Large (payload in token) | Small (session ID only) |
| Server load | None | Redis lookup per request |

**Rule:** Use JWT for stateless APIs and microservices. Use Redis sessions when you need instant revocation (admin panels, security-sensitive apps).

---

## API Response Optimization

### Compression
```typescript
import compression from 'compression';
app.use(compression({ threshold: 1024, level: 6 })); // Compress responses > 1KB
```

### Field Selection
```typescript
// Let clients request only fields they need
app.get('/users/:id', async (req, res) => {
  const fields = req.query.fields?.split(',') || ['id', 'name', 'email'];
  const allowed = ['id', 'name', 'email', 'avatar', 'role'];
  const select = Object.fromEntries(
    fields.filter(f => allowed.includes(f)).map(f => [f, true])
  );
  const user = await prisma.user.findUnique({ where: { id: req.params.id }, select });
  res.json({ data: user });
});
```

### Batch Endpoints
```typescript
// Instead of N individual requests, batch them
app.post('/users/batch', async (req, res) => {
  const ids = req.body.ids;
  if (!Array.isArray(ids) || ids.length > 100) {
    return res.status(400).json({ error: 'Max 100 IDs per batch' });
  }
  const users = await prisma.user.findMany({ where: { id: { in: ids } } });
  res.json({ data: users });
});
```



---

## Reference file: `caching-and-queues.md`

# Caching & Async Processing Reference

## Caching Strategies

### Cache-Aside (Lazy Loading) — Most Common
```typescript
async function getUser(id: string) {
  // 1. Check cache
  const cached = await redis.get(`user:${id}`);
  if (cached) return JSON.parse(cached);

  // 2. Cache miss → fetch from DB
  const user = await db.user.findUnique({ where: { id } });
  if (!user) return null;

  // 3. Populate cache with TTL
  await redis.setex(`user:${id}`, 300, JSON.stringify(user)); // 5min
  return user;
}
```
**Best for:** Read-heavy workloads, data that tolerates brief staleness.

### Write-Through (Immediate Consistency)
```typescript
async function updateUser(id: string, data: Partial<User>) {
  // 1. Write to DB
  const user = await db.user.update({ where: { id }, data });

  // 2. Immediately update cache
  await redis.setex(`user:${id}`, 300, JSON.stringify(user));

  return user;
}
```
**Best for:** Data that must be consistent between cache and DB.

### Write-Behind (Async Write)
```typescript
async function updateUserFast(id: string, data: Partial<User>) {
  // 1. Write to cache (fast)
  await redis.setex(`user:${id}`, 300, JSON.stringify({ ...existing, ...data }));

  // 2. Queue DB write (async)
  await queue.add('sync-user-to-db', { id, data });

  return { ...existing, ...data };
}
```
**Best for:** High-write throughput where brief inconsistency is acceptable.

### Cache Invalidation Patterns

| Pattern | How | When |
|---------|-----|------|
| **TTL expiry** | `setex(key, 300, value)` | Default — simple, predictable |
| **Explicit delete** | `del(key)` on write | When you need instant consistency |
| **Tag-based** | Group keys, purge by tag | Related entities (user + user's orders) |
| **Versioned keys** | `user:${id}:v${version}` | Avoid stale reads entirely |

### TTL Guidelines

| Data Type | TTL | Rationale |
|-----------|-----|-----------|
| User session | 1 hour | Security + memory |
| User profile | 5-15 min | Changes infrequently |
| Product catalog | 1-24 hours | Updates are batched |
| Config/feature flags | 30-60 sec | Needs fast propagation |
| Static assets (CDN) | 1 year | Versioned URLs |
| API responses | 1-60 min | Depends on freshness need |

---

## Redis Patterns

### Rate Limiting (Sliding Window)
```typescript
async function rateLimit(userId: string, limit = 100, windowSec = 60) {
  const now = Date.now() / 1000;
  const window = Math.floor(now / windowSec);
  const key = `rate:${userId}:${window}`;
  const prevKey = `rate:${userId}:${window - 1}`;

  const [curr, prev] = await Promise.all([redis.get(key), redis.get(prevKey)]);
  const elapsed = (now % windowSec) / windowSec;
  const estimate = (parseInt(prev || '0') * (1 - elapsed)) + parseInt(curr || '0');

  if (estimate >= limit) return { allowed: false, retryAfter: Math.ceil(windowSec * (1 - elapsed)) };

  const count = await redis.incr(key);
  if (count === 1) await redis.expire(key, windowSec * 2);
  return { allowed: true, remaining: Math.max(0, limit - Math.ceil(estimate) - 1) };
}
```

### Distributed Lock (Redlock)
```typescript
async function withLock<T>(resource: string, ttlMs: number, fn: () => Promise<T>): Promise<T> {
  const lockValue = crypto.randomBytes(16).toString('hex');
  const acquired = await redis.set(`lock:${resource}`, lockValue, 'NX', 'PX', ttlMs);

  if (acquired !== 'OK') throw new Error('Could not acquire lock');

  try {
    return await fn();
  } finally {
    // Release only if we still own it (Lua for atomicity)
    await redis.eval(
      `if redis.call("get",KEYS[1]) == ARGV[1] then return redis.call("del",KEYS[1]) else return 0 end`,
      1, `lock:${resource}`, lockValue
    );
  }
}

// Usage: prevent duplicate processing
await withLock(`process:order:${orderId}`, 30000, async () => {
  await processOrder(orderId);
});
```

### Session Storage
```typescript
async function createSession(userId: string): Promise<string> {
  const sessionId = crypto.randomUUID();
  await redis.setex(`session:${sessionId}`, 3600, JSON.stringify({
    userId, createdAt: Date.now()
  }));
  return sessionId;
}

async function getSession(sessionId: string) {
  const data = await redis.get(`session:${sessionId}`);
  if (!data) return null;
  // Extend TTL on access (sliding expiration)
  await redis.expire(`session:${sessionId}`, 3600);
  return JSON.parse(data);
}
```

### Sorted Set (Leaderboards / Rankings)
```typescript
// Add score
await redis.zadd('leaderboard', score, `user:${userId}`);

// Top 10
const top10 = await redis.zrevrange('leaderboard', 0, 9, 'WITHSCORES');

// User's rank
const rank = await redis.zrevrank('leaderboard', `user:${userId}`);
```

---

## Message Queues

### When to Use a Queue

| Scenario | Queue? | Why |
|----------|--------|-----|
| Email sending | Yes | Slow, can fail, user doesn't wait |
| Image processing | Yes | CPU-heavy, decouple from request |
| Payment processing | Maybe | Depends on UX (sync for checkout) |
| Webhook delivery | Yes | External service may be down |
| Report generation | Yes | Long-running, deliver async |
| Real-time chat | No | Use WebSockets/SSE instead |
| Simple CRUD | No | Adds unnecessary complexity |

### BullMQ (Node.js + Redis)
```typescript
import { Queue, Worker } from 'bullmq';

// Producer
const emailQueue = new Queue('email', { connection: { host: 'redis' } });

await emailQueue.add('welcome', { to: 'user@example.com', name: 'John' }, {
  attempts: 3,
  backoff: { type: 'exponential', delay: 1000 },
  removeOnComplete: 1000,
  removeOnFail: 5000
});

// Consumer
const worker = new Worker('email', async (job) => {
  await sendEmail(job.data.to, job.data.name);
}, {
  connection: { host: 'redis' },
  concurrency: 5,
  limiter: { max: 10, duration: 1000 } // 10 per second
});

worker.on('completed', (job) => console.log(`Done: ${job.id}`));
worker.on('failed', (job, err) => console.error(`Failed: ${job?.id}`, err));
```

### Queue-Based Load Leveling
```
Spike: 10,000 req/s ─→ Queue (buffer) ─→ Workers process at 1,000/s
                                          (auto-scale based on queue depth)
```

```typescript
// Producer: Enqueue immediately, respond fast
app.post('/process', async (req, res) => {
  const job = await queue.add('process', req.body);
  res.json({ jobId: job.id, status: 'queued' });
});

// Consumer: Process at sustainable rate
const worker = new Worker('process', async (job) => {
  await heavyProcessing(job.data);
}, { concurrency: 10 });
```

---

## Event-Driven Architecture

### Pub/Sub Pattern
```typescript
// Publisher (doesn't know who listens)
await redis.publish('order:created', JSON.stringify({ orderId, userId, total }));

// Subscriber 1: Send confirmation email
redis.subscribe('order:created', (message) => {
  const order = JSON.parse(message);
  emailQueue.add('order-confirmation', order);
});

// Subscriber 2: Update analytics
redis.subscribe('order:created', (message) => {
  const order = JSON.parse(message);
  analyticsQueue.add('track-purchase', order);
});

// Subscriber 3: Notify warehouse
redis.subscribe('order:created', (message) => {
  const order = JSON.parse(message);
  warehouseQueue.add('prepare-shipment', order);
});
```

### CQRS (Command Query Responsibility Segregation)
```
Write path: API → Command Handler → Write DB (normalized)
                                  → Publish event
Read path:  API → Query Handler → Read DB/Cache (denormalized, optimized for reads)
                                  ← Event → Update read model
```

```typescript
// Write side: Normalize, validate, enforce business rules
async function createOrder(cmd: CreateOrderCommand) {
  const order = await writeDb.orders.create({ data: cmd });
  await eventBus.publish('order.created', order);
  return order.id;
}

// Read side: Denormalized, fast, optimized for specific queries
eventBus.subscribe('order.created', async (event) => {
  await readDb.orderViews.upsert({
    where: { orderId: event.id },
    create: {
      orderId: event.id,
      customerName: event.customerName, // Denormalized!
      total: event.total,
      itemCount: event.items.length
    }
  });
});

// Query the read model (no joins needed)
async function getOrderDashboard(customerId: string) {
  return readDb.orderViews.findMany({ where: { customerId } });
}
```

**When CQRS is worth it:**
- Read and write patterns are very different
- Read:write ratio > 10:1
- Need different scaling strategies for reads vs writes
- Complex read queries that would require expensive joins

**When CQRS is overkill:**
- Simple CRUD applications
- Low traffic (< 1000 req/s)
- Read and write models are nearly identical



---

## Reference file: `database-scaling.md`

# Database Scaling Reference

## Indexing Strategy

### Index Type Selection

| Type | Use Case | Example |
|------|----------|---------|
| **B-tree** (default) | Equality, range, sorting | `WHERE id = 1`, `ORDER BY date` |
| **GIN** | Arrays, JSONB, full-text search | `WHERE tags @> ARRAY['a']` |
| **GiST** | Geometric, spatial, nearest-neighbor | PostGIS, `ORDER BY location <->` |
| **BRIN** | Large tables with natural ordering | Time-series > 100GB |

### Compound Index Rules

Order columns: **equality → range → sort**

```sql
-- Query: WHERE customer_id = X AND status IN (...) AND created_at > Y ORDER BY id
CREATE INDEX idx_orders ON orders(customer_id, status, created_at, id);
```

### Partial Indexes (index what you query)
```sql
-- Only index active users (90% smaller, 90% faster writes)
CREATE INDEX idx_active_users ON users(email) WHERE status = 'active';

-- Only index pending orders
CREATE INDEX idx_pending_orders ON orders(customer_id) WHERE status = 'pending';
```

### Covering Indexes (avoid heap lookups)
```sql
-- Query only needs total and date — include them in index
CREATE INDEX idx_orders_covering ON orders(customer_id)
INCLUDE (total, created_at);

-- This query is satisfied entirely by the index (index-only scan)
SELECT total, created_at FROM orders WHERE customer_id = 123;
```

### Index Anti-Patterns
- Indexing every column (slows writes, wastes storage)
- Indexing low-cardinality columns alone (status with 3 values → useless)
- Missing indexes on foreign keys (kills JOIN performance)
- Unused indexes (check `pg_stat_user_indexes` for `idx_scan = 0`)

---

## Query Optimization

### EXPLAIN ANALYZE — Always Profile
```sql
EXPLAIN (ANALYZE, BUFFERS, TIMING ON)
SELECT * FROM orders WHERE customer_id = 123 AND created_at > NOW() - INTERVAL '30d';
```

**Red flags in output:**
- `Seq Scan` on large table → missing index
- `Filter` removes most rows → index should be more selective
- `Sort` with high cost → add index that matches ORDER BY
- `Nested Loop` with large outer table → consider hash/merge join

### pg_stat_statements — Find Problem Queries
```sql
-- Top 10 slowest queries by total time
SELECT query, calls, total_exec_time / 1000 AS total_sec,
       mean_exec_time AS avg_ms,
       100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS cache_pct
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 10;

-- N+1 detector: queries called many times with low individual cost
SELECT query, calls, mean_exec_time AS avg_ms
FROM pg_stat_statements
WHERE calls > 1000 AND mean_exec_time < 5
ORDER BY calls DESC LIMIT 10;
```

---

## N+1 Query Prevention

### Prisma
```typescript
// BAD: 1 + N queries
const users = await prisma.user.findMany();
for (const u of users) {
  u.posts = await prisma.post.findMany({ where: { authorId: u.id } });
}

// GOOD: 2 queries (parallel fetch)
const users = await prisma.user.findMany({ include: { posts: true } });

// GOOD: Single query (database JOIN)
const users = await prisma.user.findMany({
  relationLoadStrategy: 'join',
  include: { posts: { select: { id: true, title: true } } }
});
```

### TypeORM
```typescript
// BAD: N+1
const users = await repo.find();
for (const u of users) u.posts = await postRepo.find({ where: { userId: u.id } });

// GOOD: JOIN
const users = await repo.createQueryBuilder('user')
  .leftJoinAndSelect('user.posts', 'posts')
  .getMany();
```

### Drizzle (no N+1 by design)
```typescript
const results = await db.select().from(users)
  .leftJoin(posts, eq(users.id, posts.userId));
```

### Detection
Enable query logging and look for: **query count = 1 + N** where N = row count.

```typescript
// Prisma query logging
const prisma = new PrismaClient({ log: [{ emit: 'event', level: 'query' }] });
prisma.$on('query', (e) => {
  if (e.duration > 100) console.warn(`SLOW: ${e.duration}ms — ${e.query}`);
});
```

---

## Connection Pooling

### Sizing Formula
```
pool_size = (CPU cores × 2) + effective_spindle_count

4-core  → 9 connections
8-core  → 17 connections
16-core → 33 connections
```

### PgBouncer Configuration
```ini
[pgbouncer]
pool_mode = transaction          # Release after each transaction
default_pool_size = 25           # Per database/user pair
min_pool_size = 10               # Keep warm
reserve_pool_size = 5            # Overflow buffer
max_client_connections = 1000    # Total client limit
server_idle_timeout = 600        # Close idle server connections (10min)
query_wait_timeout = 120         # Max wait for available connection
```

### Application-Level (Prisma)
```env
# Prisma uses internal pool; configure via connection string
DATABASE_URL="postgresql://user:pass@host/db?connection_limit=25&pool_timeout=10"
```

### Connection Pool Monitoring
```sql
-- PostgreSQL: Check active connections
SELECT count(*) FROM pg_stat_activity WHERE state = 'active';

-- Check connection limit
SHOW max_connections;

-- Per-database usage
SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;
```

**Warning signs:** Pool utilization > 80%, rising wait times, connection timeouts.

---

## Read Replicas

### When to Add
- Read:write ratio exceeds **10:1**
- Primary CPU consistently > 70% from read queries
- Analytics queries competing with transactional reads

### Routing Pattern
```typescript
// Simple: Route by operation type
const primaryPool = new Pool({ host: 'primary.db.com' });
const replicaPool = new Pool({ host: 'replica.db.com' });

async function query(sql: string, params: any[], opts?: { write?: boolean }) {
  const pool = opts?.write ? primaryPool : replicaPool;
  return pool.query(sql, params);
}

// Read from replica
const users = await query('SELECT * FROM users WHERE id = $1', [id]);

// Write to primary
await query('INSERT INTO users (name) VALUES ($1)', [name], { write: true });
```

### Replication Lag
- Typical: 5-50ms for well-tuned async replication
- **Read-your-writes consistency**: After a write, read from primary for that user's session
- **Analytics queries**: Always safe on replicas (stale data acceptable)

---

## Partitioning

### When to Partition
- Table exceeds **100GB** or **100M+ rows**
- Queries always filter on a specific column (date, tenant)
- Need fast deletion of old data (`DROP` partition vs `DELETE`)

### Range Partitioning (time-series)
```sql
CREATE TABLE events (
  id BIGSERIAL, created_at TIMESTAMPTZ NOT NULL, data JSONB
) PARTITION BY RANGE (created_at);

CREATE TABLE events_2025_01 PARTITION OF events
  FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE TABLE events_2025_02 PARTITION OF events
  FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

-- Delete old data instantly
DROP TABLE events_2024_01; -- 0.01s vs DELETE which could take minutes
```

### Hash Partitioning (even distribution)
```sql
CREATE TABLE orders (id BIGSERIAL, customer_id INT, data JSONB)
PARTITION BY HASH (customer_id);

CREATE TABLE orders_0 PARTITION OF orders FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE orders_1 PARTITION OF orders FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE orders_2 PARTITION OF orders FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE orders_3 PARTITION OF orders FOR VALUES WITH (MODULUS 4, REMAINDER 3);
```

**Rule:** Keep partition count under 500 — query planning overhead grows with partition count.

---

## Sharding

### When to Shard (Last Resort)
- Single database can't handle write volume
- Data exceeds what fits on one server (multi-TB)
- Need geographic data locality

### Sharding Strategies
| Strategy | Pros | Cons |
|----------|------|------|
| **Hash-based** | Even distribution | No range queries on shard key |
| **Range-based** | Range queries work | Hot shards if distribution skewed |
| **Tenant-based** | Strong isolation | Uneven if tenants vary in size |

### Before Sharding, Try These First
1. Add proper indexes
2. Fix N+1 queries
3. Add read replicas
4. Add caching layer
5. Partition large tables
6. Vertical scaling (bigger instance)
7. Archive old data
8. Optimize queries with EXPLAIN ANALYZE

---

## Denormalization

### Decision Matrix

| Scenario | Keep Normalized | Denormalize |
|----------|----------------|-------------|
| High write volume | Yes | No |
| High read volume, slow joins | No | Yes |
| Data consistency critical | Yes | No |
| Analytics / reporting | No | Yes (materialized views) |

### Materialized Views
```sql
-- Precompute expensive aggregation
CREATE MATERIALIZED VIEW order_stats AS
SELECT customer_id, COUNT(*) AS order_count, SUM(total) AS total_spent
FROM orders GROUP BY customer_id;

-- Refresh periodically (not on every write)
REFRESH MATERIALIZED VIEW CONCURRENTLY order_stats;
-- CONCURRENTLY allows reads during refresh (requires unique index)

CREATE UNIQUE INDEX ON order_stats(customer_id);
```

**Rule:** Start normalized. Denormalize specific queries only when EXPLAIN shows expensive joins that caching can't solve.



---

## Reference file: `infrastructure.md`

# Infrastructure Scaling Reference

## Kubernetes Autoscaling (HPA)

### Configuration
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2            # Always 2+ for HA (never 1 in production)
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70    # Scale up at 70% CPU
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0     # Scale up immediately
      policies:
      - type: Percent
        value: 100                       # Can double capacity
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300   # Wait 5min before scaling down
      policies:
      - type: Percent
        value: 50                        # Max 50% reduction per cycle
        periodSeconds: 60
```

### Resource Requests & Limits
```yaml
resources:
  requests:                    # What HPA bases utilization on
    cpu: 250m                  # Reserve 250 milliCPU
    memory: 512Mi
  limits:
    cpu: 500m                  # Hard cap
    memory: 1Gi
```

**Rules:**
- HPA measures % of **request**, not limit
- If request=250m, actual=175m → utilization=70% → triggers scale
- `minReplicas: 2+` in production (single pod = downtime during restart)
- Target utilization 50-70% gives spike headroom

### Custom Metrics Scaling
```yaml
# Scale on queue depth instead of CPU
metrics:
- type: External
  external:
    metric:
      name: queue_depth
      selector:
        matchLabels:
          queue: email-processing
    target:
      type: AverageValue
      averageValue: "100"     # 1 pod per 100 queued messages
```

---

## Serverless Patterns

### Cold Start Optimization
```typescript
// Lazy-load heavy dependencies
let dbClient: PrismaClient | null = null;

export const handler = async (event: any) => {
  // Initialize only on first invocation (reused across warm invocations)
  if (!dbClient) {
    const { PrismaClient } = await import('@prisma/client');
    dbClient = new PrismaClient();
  }

  return dbClient.user.findMany();
};
```

**Cold start costs by memory:**
| Memory | Cold Start | Cost/invocation |
|--------|-----------|----------------|
| 256MB | ~400ms | $0.0000004 |
| 512MB | ~280ms | $0.0000008 |
| 1024MB | ~150ms | $0.0000017 |

**Rule:** Allocate 1.5x typical memory usage — faster execution + faster cold starts.

### Provisioned Concurrency
- Cost: ~$0.015/unit/hour ($10.80/month per unit)
- Use only when: Cold start latency violates SLA
- Alternative: Keep a minimum of warm instances via scheduled pings

---

## CDN Caching

### Cache-Control Headers
```typescript
// Static assets (versioned URLs — cache forever)
res.set('Cache-Control', 'public, max-age=31536000, immutable');

// API responses (cache at edge, short client cache)
res.set('Cache-Control', 'public, max-age=0, s-maxage=3600, stale-while-revalidate=60');

// Private/authenticated content
res.set('Cache-Control', 'private, max-age=300');

// Never cache
res.set('Cache-Control', 'no-store');
```

### Header Reference

| Header | Meaning |
|--------|---------|
| `max-age=N` | Browser caches for N seconds |
| `s-maxage=N` | CDN caches for N seconds (overrides max-age at edge) |
| `immutable` | Never revalidate (use with hashed filenames) |
| `stale-while-revalidate=N` | Serve stale for N seconds while refreshing in background |
| `private` | Only browser caches (not CDN) — use for user-specific data |
| `no-store` | Never cache anywhere |

### Cache Busting via Content Hashing
```javascript
// Webpack/Vite: Auto-hash filenames
output: { filename: '[name].[contenthash].js' }

// Result: app.a3f9d2c1.js → new hash on every change
// Combine with: Cache-Control: public, max-age=31536000, immutable
// No purging needed — new URL = new request
```

---

## Deployments

### Blue-Green (Zero Downtime, Instant Rollback)
```
1. Deploy v2 alongside v1 (both running)
2. Test v2 thoroughly
3. Switch load balancer: v1 → v2
4. Keep v1 for 1 hour (instant rollback)
5. Decommission v1
```
**Tradeoff:** Requires 2x resources during deployment.

### Canary (Gradual, Lower Risk)
```
1. Deploy v2 to 1 pod (5% traffic)
2. Monitor errors + latency for 5min
3. If healthy: ramp to 25% → 50% → 100%
4. If unhealthy: auto-rollback to v1
```
```yaml
# Flagger canary config
analysis:
  interval: 1m
  threshold: 5
  maxWeight: 50
  stepWeight: 10          # +10% per minute
  metrics:
  - name: request-success-rate
    thresholdRange: { min: 99 }   # Require 99%+ success
  - name: request-duration
    thresholdRange: { max: 500 }  # p99 < 500ms
```

### Database Migrations in Deployments
```sql
-- SAFE: Backward compatible (both versions work)
ALTER TABLE users ADD COLUMN new_field TEXT DEFAULT '';

-- UNSAFE: Breaks old version
ALTER TABLE users DROP COLUMN old_field;
ALTER TABLE users RENAME COLUMN name TO full_name;
```

**Rule:** Always deploy in 3 phases:
1. Add new column (backward compatible)
2. Deploy new code that uses new column
3. Remove old column (after old code is gone)

---

## Observability

### The Four Golden Signals
| Signal | What to Measure | Alert When |
|--------|----------------|------------|
| **Latency** | p50, p95, p99 response time | p99 > 500ms |
| **Traffic** | Requests per second | Unusual spike or drop |
| **Errors** | Error rate (5xx / total) | > 1% error rate |
| **Saturation** | CPU, memory, DB connections, queue depth | > 80% utilization |

### Structured Logging
```typescript
import pino from 'pino';
const logger = pino({ level: 'info' });

// GOOD: Structured, searchable
logger.info({ userId: '123', action: 'login', duration: 45 }, 'User logged in');
// Output: {"level":30,"userId":"123","action":"login","duration":45,"msg":"User logged in"}

// BAD: Unstructured
console.log(`User 123 logged in in 45ms`);
```

### Request Tracing
```typescript
import { v4 as uuid } from 'uuid';

// Middleware: Add trace ID to every request
app.use((req, res, next) => {
  req.traceId = req.headers['x-trace-id'] || uuid();
  res.setHeader('x-trace-id', req.traceId);
  next();
});

// Include in all logs
logger.info({ traceId: req.traceId, path: req.path }, 'Request started');

// Pass to downstream services
const response = await fetch('https://service-b.internal/api', {
  headers: { 'x-trace-id': req.traceId }
});
```

### Key Metrics to Track

```typescript
import { Counter, Histogram, Gauge } from 'prom-client';

// Request duration (histogram for percentiles)
const httpDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]
});

// Error counter
const httpErrors = new Counter({
  name: 'http_errors_total',
  help: 'HTTP errors',
  labelNames: ['method', 'route', 'status']
});

// Active connections gauge
const dbConnections = new Gauge({
  name: 'db_active_connections',
  help: 'Active database connections'
});

// Middleware
app.use((req, res, next) => {
  const end = httpDuration.startTimer({ method: req.method, route: req.route?.path });
  res.on('finish', () => {
    end({ status: res.statusCode });
    if (res.statusCode >= 500) {
      httpErrors.inc({ method: req.method, route: req.route?.path, status: res.statusCode });
    }
  });
  next();
});
```

---

## Concurrency Patterns

### Worker Threads (CPU-bound work)
```typescript
import { Worker, isMainThread, parentPort } from 'worker_threads';

if (isMainThread) {
  // Main thread: Offload CPU-heavy work
  async function processImage(buffer: Buffer): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      const worker = new Worker(__filename, { workerData: { buffer } });
      worker.on('message', resolve);
      worker.on('error', reject);
    });
  }
} else {
  // Worker thread: Do the heavy lifting
  const { workerData } = require('worker_threads');
  const result = heavyImageProcessing(workerData.buffer);
  parentPort?.postMessage(result);
}
```

### Cluster Mode (Multi-process)
```typescript
import cluster from 'cluster';
import os from 'os';

if (cluster.isPrimary) {
  const numWorkers = os.cpus().length;
  for (let i = 0; i < numWorkers; i++) cluster.fork();

  cluster.on('exit', (worker) => {
    console.error(`Worker ${worker.process.pid} died, replacing...`);
    cluster.fork();
  });
} else {
  // Each worker runs the HTTP server
  app.listen(3000);
}
```

### Backpressure (Prevent Overload)
```typescript
// Stream processing with backpressure
import { Transform } from 'stream';

const processor = new Transform({
  highWaterMark: 1000, // Buffer max 1000 chunks
  transform(chunk, encoding, callback) {
    processChunk(chunk)
      .then(result => callback(null, result))
      .catch(err => callback(err));
  }
});

// Pipeline automatically handles backpressure
inputStream.pipe(processor).pipe(outputStream);
```

### Semaphore (Limit Concurrent Operations)
```typescript
class Semaphore {
  private queue: (() => void)[] = [];
  private running = 0;

  constructor(private max: number) {}

  async acquire(): Promise<void> {
    if (this.running < this.max) { this.running++; return; }
    return new Promise(resolve => this.queue.push(resolve));
  }

  release(): void {
    this.running--;
    const next = this.queue.shift();
    if (next) { this.running++; next(); }
  }
}

// Limit to 10 concurrent DB operations
const sem = new Semaphore(10);
async function queryWithLimit(sql: string) {
  await sem.acquire();
  try { return await db.query(sql); }
  finally { sem.release(); }
}
```

---

## Load Testing

### Before Optimizing, Profile
```bash
# Quick load test with k6
k6 run --vus 50 --duration 30s script.js

# Artillery (Node.js)
npx artillery quick --count 50 --num 100 http://localhost:3000/api/users
```

### What to Measure During Load Tests

| Metric | Tool | Warning Sign |
|--------|------|-------------|
| p99 latency | k6, Artillery | > 500ms |
| Throughput | k6 | Plateaus while CPU < 100% (IO bottleneck) |
| Error rate | k6 | > 0 (should be zero under expected load) |
| DB connections | pg_stat_activity | Near max_connections |
| Memory | top/htop | Continuously growing (leak) |
| CPU per process | top | Single core at 100% (need cluster mode) |

**Rule:** Test at 2x expected peak traffic. If it survives, you have margin.

