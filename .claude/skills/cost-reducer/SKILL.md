---
name: "cost-reducer"
description: "Reduce cloud, infrastructure, and operational costs while maintaining performance. Use when writing database queries, configuring cloud resources, optimizing bundles, setting up caching, choosing between services, sizing instances, configuring CDN, managing storage, or reviewing code for cost inefficiencies. Covers AWS/GCP/Vercel pricing, database optimization, serverless tuning, image pipelines, observability costs, and FinOps practices."
---

# Cost Reducer

You are a cost-conscious engineer. You write code that performs well AND costs less to run. You know that the fastest way to burn money is slow queries, bloated bundles, misconfigured infrastructure, and unmonitored spend.

Read the detailed reference files in `${CLAUDE_SKILL_DIR}` for comprehensive patterns:

- `code-level-savings.md` — Bundle optimization, image pipelines, query cost reduction, N+1 prevention, caching ROI, memory leak detection
- `cloud-and-infra.md` — Instance right-sizing, serverless tuning, storage tiers, data transfer traps, container optimization, CI/CD costs
- `services-and-finops.md` — Service pricing comparisons, observability cost control, auth provider economics, FinOps practices, unit economics

## The Cost-Conscious Mindset

**Rule #1: The cheapest code is code that doesn't run.** Cache it, skip it, or make it smaller.

### Cost Impact Hierarchy (Highest to Lowest Savings)

```
1. Architecture choices     → 10x cost difference (serverless vs always-on, managed vs self-hosted)
2. Data transfer routing    → $100-500/month (NAT gateway traps, cross-region, egress)
3. Right-sizing compute     → $50-300/month (overprovisioned instances, idle resources)
4. Database optimization    → $50-200/month (missing indexes, N+1 queries, wrong instance)
5. Caching                  → $50-200/month (reduces DB load, enables smaller instances)
6. Storage optimization     → $30-200/month (lifecycle policies, compression, tiering)
7. Bundle/image optimization→ $50-200/month per 1M users (CDN bandwidth)
8. Observability tuning     → $10-100/month (log sampling, trace sampling, retention)
```

## Quick Wins — Do These First

### 1. Enable S3 Intelligent-Tiering
```bash
# Zero-effort storage savings — auto-moves data to cheaper tiers
aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket my-bucket --id auto-tier \
  --intelligent-tiering-configuration '{"Id":"auto-tier","Status":"Enabled","Tierings":[{"Days":90,"AccessTier":"ARCHIVE_ACCESS"}]}'
```
**Saves:** 40-68% on infrequently accessed data.

### 2. Fix N+1 Queries
```typescript
// BAD: 101 queries for 100 users — wastes DB compute
const users = await prisma.user.findMany();
for (const u of users) u.posts = await prisma.post.findMany({ where: { authorId: u.id } });

// GOOD: 2 queries total — enables smaller DB instance
const users = await prisma.user.findMany({ include: { posts: true } });
```
**Saves:** $50-150/month by reducing DB instance size.

### 3. Convert Images to WebP/AVIF
```typescript
import sharp from 'sharp';
await sharp('input.jpg').webp({ quality: 85 }).toFile('output.webp');  // 25-35% smaller
await sharp('input.jpg').avif({ quality: 75 }).toFile('output.avif');  // 50% smaller
```
**Saves:** 30-50% on CDN bandwidth costs.

### 4. Add Cache for Read-Heavy Queries
```typescript
async function getUser(id: string) {
  const cached = await redis.get(`user:${id}`);
  if (cached) return JSON.parse(cached);
  const user = await db.user.findUnique({ where: { id } });
  await redis.setex(`user:${id}`, 300, JSON.stringify(user));
  return user;
}
```
**Saves:** 85% reduction in DB queries → enables DB downsizing.

### 5. Replace NAT Gateway with VPC Endpoints
```
NAT Gateway: $0.045/GB + $0.065/hour = $275+/month for 100GB
VPC Gateway Endpoint (S3): FREE
VPC Interface Endpoint: $0.01/GB = 78% cheaper
```

### 6. Set Log Retention Policies
```bash
aws logs put-retention-policy --log-group-name /aws/lambda/my-fn --retention-in-days 7
```
**Saves:** 75% on CloudWatch Logs storage (30-day → 7-day).

## Cost Detection Checklist

When reviewing code or infrastructure, scan for these red flags:

| Red Flag | Cost Impact | Fix |
|----------|------------|-----|
| N+1 queries | DB compute waste | Eager loading / JOINs |
| Missing DB indexes | Slow queries → bigger instance | Add targeted indexes |
| `import *` or full SDK imports | Larger bundles → more bandwidth | Tree-shake, selective imports |
| Uncompressed images (JPEG/PNG) | 2-3x bandwidth cost | WebP/AVIF pipeline |
| Hardcoded large instance sizes | Overpaying for idle capacity | Right-size via metrics |
| NAT Gateway for AWS service traffic | $0.045/GB wasted | VPC Endpoints |
| No cache on read-heavy paths | DB handles every request | Redis cache-aside |
| 30-day log retention on all groups | Storage waste | 7-day for non-critical |
| High-cardinality metrics | Observability bill explosion | Aggregate, remove user IDs |
| Memory leaks | OOM restarts → cold start costs | Profile and fix leaks |
| No S3 lifecycle policies | Paying full price for old data | Intelligent-Tiering |
| Provisioned concurrency everywhere | 17x Lambda cost | Use only where SLA requires |

## Critical Rules

1. **Measure before cutting** — Use billing dashboards, Cost Explorer, or Kubecost; don't guess
2. **Optimize the biggest line item first** — $100 saved on compute beats $5 saved on logs
3. **Cache reads, queue writes** — Caching reduces DB load; queues smooth traffic spikes
4. **Right-size to actual usage** — Instance CPU < 30% average = overpaying
5. **Compress everything** — gzip responses, WebP images, minified bundles
6. **Set TTLs and lifecycle policies** — Data without expiry accumulates cost forever
7. **Use reserved/savings plans for steady state** — 40-72% discount on predictable workloads
8. **Spot instances for fault-tolerant work** — 90% discount for batch processing, CI/CD
9. **Tag everything** — Cost allocation tags enable accountability and anomaly detection
10. **Track unit economics** — Cost per request, cost per user, cost per transaction

Use `$ARGUMENTS` to focus on a specific cost area. Read the relevant reference file before making recommendations.


# Appendix: Bundled Reference Files


---

## Reference file: `cloud-and-infra.md`

# Cloud & Infrastructure Cost Reference

## Instance Right-Sizing

### Detection
```
If average CPU < 30% → instance is oversized
If average CPU > 70% → approaching capacity
Sweet spot: 40-60% average CPU utilization
```

### EC2 Pricing Strategy
| Strategy | Discount | Commitment | Use For |
|----------|----------|-----------|---------|
| On-Demand | 0% | None | Variable/unpredictable load |
| Savings Plans | 40-60% | 1-3 year | Steady baseline compute |
| Reserved | 50-72% | 1-3 year | Specific instance types |
| Spot | Up to 90% | None (2-min interruption) | Batch, CI/CD, fault-tolerant |

**Hybrid approach** (40-60% total savings):
- Baseline (24/7 load): Savings Plans
- Variable load: On-Demand
- Batch/CI: Spot instances

### Kubernetes Right-Sizing
```yaml
# Step 1: Monitor actual usage with metrics-server
kubectl top pods -n production

# Step 2: Compare requests vs actual
# If request=500m CPU but actual=80m → overprovisioned 6x

# Step 3: Right-size
resources:
  requests:
    cpu: 100m       # Match actual + 25% buffer
    memory: 128Mi
  limits:
    cpu: 200m       # 2x request for burst
    memory: 256Mi
```
**Savings:** Right-sizing typically saves 30-70% on compute costs.

---

## Serverless Cost Optimization

### Lambda Memory Tuning

```
Memory vs Cost (10M invocations/month):
128MB:  $21/month  — 8s avg (slow, cheap per-ms but long duration)
256MB:  $38/month  — 4.5s avg
512MB:  $75/month  — 2.2s avg (sweet spot for most workloads)
1024MB: $150/month — 1.1s avg (for CPU-bound)
2048MB: $300/month — 700ms avg (overkill for I/O-bound)
```

**Rule:** Use AWS Lambda Power Tuning to find the cost-optimal memory. Often 512MB is cheapest overall (shorter duration offsets higher per-ms cost).

### Provisioned Concurrency — Usually Overkill
```
On-demand invocation: $0.0000002 per request
Provisioned concurrency: $0.015/unit/hour = $10.80/month per unit

10 units = $108/month — just to keep functions warm
```
**Only use when:** Cold start latency violates a revenue-impacting SLA.
**Alternative:** Scheduled warm-up pings (80-95% warm at 5-15% the cost).

### Lambda Best Practices
```typescript
// Initialize OUTSIDE handler (reused across warm invocations)
const s3 = new S3Client({});
let dbPool: Pool | null = null;

export const handler = async (event: any) => {
  if (!dbPool) dbPool = new Pool({ max: 1 }); // Lazy init, reused
  const result = await dbPool.query('SELECT 1');
  return { statusCode: 200, body: JSON.stringify(result) };
};
```

### API Gateway Cost Trap
```
1B HTTP API requests/month:
  Requests: $900
  Execution logging: $530  ← 37% of total spend!

Fix: Disable execution logging in production
     Use HTTP APIs instead of REST APIs (71% cheaper)
```

### Graviton (ARM) Instances
- Lambda ARM: 20% cheaper + often faster than x86
- EC2 Graviton: 20-40% better price-performance
```yaml
# Lambda: Add architecture
Runtime: nodejs20.x
Architectures: [arm64]  # 20% cheaper
```

---

## Data Transfer Cost Traps

### The NAT Gateway Problem
```
NAT Gateway costs:
  Hourly: $0.065/hour = $47.45/month
  Data processing: $0.045/GB

100GB/month through NAT:
  $47.45 + (100 × $0.045) = $51.95/month

vs VPC Gateway Endpoint (S3/DynamoDB): FREE
vs VPC Interface Endpoint: $8.76/month + $0.01/GB = $9.76/month
```

**Fix priority:**
1. S3 traffic → Gateway Endpoint (free)
2. DynamoDB traffic → Gateway Endpoint (free)
3. Other AWS services → Interface Endpoints (78% cheaper than NAT)
4. Internet traffic → Only thing that needs NAT

### Cross-Region Transfer
```
Same region: Free (within same AZ) or $0.01/GB (cross-AZ)
Cross-region: $0.02/GB
Internet egress: $0.09/GB (first 10TB)

Rule: Keep data and compute in the same region
```

### CloudFront vs Direct S3
```
Direct S3 egress: $0.09/GB
CloudFront: $0.085/GB (cheaper!) + caching reduces origin fetches

3TB/month:
  Direct S3: $270
  CloudFront: $127.50 + $15 origin fetch = $142.50
  Savings: $127.50/month
```

---

## Storage Optimization

### S3 Lifecycle Policies
```json
{
  "Rules": [
    {
      "ID": "archive-logs",
      "Filter": { "Prefix": "logs/" },
      "Transitions": [
        { "Days": 30, "StorageClass": "STANDARD_IA" },
        { "Days": 90, "StorageClass": "GLACIER" }
      ]
    },
    {
      "ID": "delete-old-builds",
      "Filter": { "Prefix": "ci-builds/" },
      "Expiration": { "Days": 30 }
    }
  ]
}
```

### Storage Cost Comparison
| Tier | $/GB/month | Access Cost | Use For |
|------|-----------|-------------|---------|
| S3 Standard | $0.023 | Free GETs | Frequently accessed |
| S3 Infrequent | $0.0125 | $0.01/1K GETs | Monthly access |
| S3 Glacier Instant | $0.004 | $0.01/1K GETs | Quarterly access |
| S3 Glacier Deep | $0.00099 | $0.02/1K GETs + hours retrieval | Yearly/archive |

**Rule:** Enable Intelligent-Tiering on all buckets. It auto-moves data and costs nothing if data is accessed frequently.

---

## Container Optimization

### Multi-Stage Docker Builds
```dockerfile
# Build stage (includes dev tools)
FROM node:20 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage (minimal)
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./
CMD ["node", "dist/index.js"]
```

**Image size comparison:**
| Base Image | Size |
|-----------|------|
| node:20 (debian) | 1.1GB |
| node:20-alpine | 180MB |
| distroless/nodejs20 | 130MB |

**Cost savings per 100 deploys/month:**
- 1.1GB → 180MB = 920MB saved per pull
- 100 deploys × 920MB = 92GB less transfer
- At $0.09/GB = **$8.28/month** + faster deploys

---

## CI/CD Cost Reduction

### Build Caching
```yaml
# GitHub Actions: Cache node_modules
- uses: actions/cache@v4
  with:
    path: node_modules
    key: ${{ runner.os }}-node-${{ hashFiles('package-lock.json') }}

# Docker layer caching
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

**Impact:** 10-minute build → 30-second build (cached) = 95% reduction in CI compute.

### Self-Hosted Runners
```
GitHub Actions: $0.008/minute (Linux)
  100 builds/month × 10 min = 1000 min = $8/month (cheap for small teams)

At scale: 10,000 builds/month × 10 min = $800/month
Self-hosted EC2 spot: ~$15/month
Savings at scale: $785/month
```

**Rule:** Use GitHub-hosted for small teams. Self-host at > 5000 minutes/month.

### Parallel vs Sequential
```yaml
# Sequential: 10 + 5 + 3 = 18 minutes
jobs:
  lint: ...
  test: { needs: lint }
  build: { needs: test }

# Parallel: max(10, 5, 3) = 10 minutes (44% faster)
jobs:
  lint: ...
  test: ...        # No dependency on lint
  build: ...       # Only depends on test passing
```

---

## Database Pricing Comparisons

### PostgreSQL (10GB, 100 QPS peak)

| Provider | Monthly Cost | Notes |
|----------|-------------|-------|
| AWS RDS db.t4g.medium | $65 | Managed, Multi-AZ extra |
| Supabase Pro | $45-50 | Includes auth, realtime, storage |
| Neon Launch | $22.50 | Scale-to-zero, cheapest for bursty |
| PlanetScale (MySQL) | $39 | Branching, serverless |

**Rule:** Neon for dev/bursty, Supabase for full-stack, RDS for enterprise/control.

### Redis

| Provider | Monthly Cost | Notes |
|----------|-------------|-------|
| ElastiCache cache.t4g.micro | $12.24 | AWS managed |
| Upstash | $0-10 | Pay-per-request, scale-to-zero |
| Redis Cloud | $7 | Managed, free tier |

**Rule:** Upstash for low-traffic/serverless. ElastiCache for predictable high-traffic.

---

## Real-World Pricing Scenario

### E-Commerce (1M Users, 1M Orders/Month)

**Before optimization:**
```
RDS db.t4g.large:      $108/month  (N+1 queries, missing indexes)
Lambda (untuned):       $150/month  (1024MB, could be 512MB)
S3 Standard (50TB):    $1,150/month (no lifecycle policies)
NAT Gateway:            $275/month  (S3 traffic going through NAT)
CloudWatch Logs:        $50/month   (30-day retention, all levels)
Vercel bandwidth (3TB): $300/month  (unoptimized bundles/images)
TOTAL:                 $2,033/month
```

**After optimization:**
```
RDS db.t4g.micro + Redis: $23/month   (caching + indexes → smaller DB)
Lambda (512MB, ARM):      $38/month   (right-sized + Graviton)
S3 Intelligent-Tiering:  $628/month   (auto-tiered)
VPC Endpoints:            $10/month   (replaced NAT for S3)
CloudWatch Logs:          $12/month   (7-day retention, sampling)
Vercel bandwidth (1.5TB): $75/month   (WebP + tree-shaking)
TOTAL:                   $786/month

SAVINGS: $1,247/month = $14,964/year (61% reduction)
```



---

## Reference file: `code-level-savings.md`

# Code-Level Cost Savings Reference

## Bundle Size Optimization

### Impact on Cost
- Vercel: $0.15/GB after 1TB included
- 1M users × 3MB page = 3TB = **$300/month in bandwidth**
- 35% bundle reduction → **$105/month saved**

### Tree-Shaking
```javascript
// BAD: Imports entire library (can't tree-shake)
import * as lodash from 'lodash';       // 70KB+
import { everything } from 'aws-sdk';    // 50MB+

// GOOD: Named imports (tree-shakeable)
import { debounce } from 'lodash-es';    // 1KB
import { S3Client } from '@aws-sdk/client-s3'; // 30KB
```

### Dynamic Imports (Code Splitting)
```typescript
// BAD: Heavy component loaded on every page
import HeavyChart from './HeavyChart';

// GOOD: Loaded only when needed
const HeavyChart = lazy(() => import('./HeavyChart'));

// Next.js dynamic import
const AdminPanel = dynamic(() => import('./AdminPanel'), {
  loading: () => <Skeleton />,
  ssr: false  // Skip server rendering for client-only components
});
```

### Bundle Analysis
```bash
# Analyze what's in your bundle
npx webpack-bundle-analyzer dist/stats.json

# Next.js built-in
ANALYZE=true next build

# Vite
npx vite-bundle-visualizer
```

**Common bloat sources:**
| Library | Typical Size | Lightweight Alternative |
|---------|-------------|----------------------|
| moment.js | 70KB | date-fns (tree-shakeable) or dayjs (2KB) |
| lodash | 70KB | lodash-es (tree-shakeable) or native JS |
| aws-sdk v2 | 50MB+ | @aws-sdk/client-* v3 (modular) |
| chart.js | 200KB | Load dynamically, only on chart pages |

---

## Image Optimization Pipeline

### Format Savings
| Format | vs JPEG | Browser Support |
|--------|---------|----------------|
| WebP | 25-35% smaller | 97% |
| AVIF | 50% smaller | 93% |

### Server-Side Pipeline (Sharp)
```typescript
import sharp from 'sharp';

async function optimizeForWeb(input: Buffer, filename: string) {
  const sizes = [640, 1280, 1920];
  const results = [];

  for (const width of sizes) {
    // WebP (primary)
    await sharp(input).resize(width).webp({ quality: 85 })
      .toFile(`public/img/${filename}-${width}w.webp`);

    // AVIF (modern browsers)
    await sharp(input).resize(width).avif({ quality: 75 })
      .toFile(`public/img/${filename}-${width}w.avif`);

    // JPEG fallback
    await sharp(input).resize(width).jpeg({ quality: 80, mozjpeg: true })
      .toFile(`public/img/${filename}-${width}w.jpg`);
  }
}
```

### Responsive HTML
```html
<picture>
  <source srcset="/img/hero-640w.avif 640w, /img/hero-1280w.avif 1280w" type="image/avif" />
  <source srcset="/img/hero-640w.webp 640w, /img/hero-1280w.webp 1280w" type="image/webp" />
  <img src="/img/hero-1280w.jpg" alt="Hero" loading="lazy" decoding="async" />
</picture>
```

### Next.js Image (Automatic Optimization)
```javascript
// next.config.js
module.exports = {
  images: {
    formats: ['image/avif', 'image/webp'],
    minimumCacheTTL: 86400 * 365,  // Cache 1 year
    deviceSizes: [640, 828, 1200, 1920],
  }
};
```

**Cost impact:** 1M image requests/month × 500KB avg → 500GB bandwidth.
With WebP: 325GB → **saves $26/month** at $0.15/GB.

---

## Database Query Cost

### Expensive Query Detection
```sql
-- Find queries that cost the most total time
SELECT query, calls, total_exec_time / 1000 AS total_sec, mean_exec_time AS avg_ms
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;

-- Find sequential scans on large tables (missing indexes)
SELECT schemaname, relname, seq_scan, seq_tup_read,
       idx_scan, idx_tup_fetch
FROM pg_stat_user_tables
WHERE seq_scan > 100 AND seq_tup_read > 10000
ORDER BY seq_tup_read DESC;
```

### Index Cost of Queries
```sql
-- Before: Sequential scan, costs 1000 units, 150ms
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 123 AND status = 'active';
-- Seq Scan on orders  (cost=0.00..1000.00 rows=5000)
-- Execution Time: 156.234 ms

-- After: Add targeted index
CREATE INDEX idx_orders_customer_status ON orders(customer_id, status);

-- Now: Index scan, costs 0.4 units, 3ms (50x faster)
-- Index Scan using idx_orders_customer_status  (cost=0.00..0.40 rows=5)
-- Execution Time: 3.234 ms
```

**Cost translation:** Reducing avg query time from 150ms to 3ms means the same DB instance handles 50x more queries → downsize from db.t4g.large ($108/month) to db.t4g.micro ($10.80/month). **Saves $97/month.**

### N+1 Query Prevention
```typescript
// Prisma — use include (2 queries instead of N+1)
const users = await prisma.user.findMany({
  include: { posts: true, orders: { select: { id: true, total: true } } }
});

// GraphQL — use DataLoader (batches within request)
const userLoader = new DataLoader(async (ids) => {
  const users = await db.user.findMany({ where: { id: { in: ids } } });
  return ids.map(id => users.find(u => u.id === id));
});
```

### Materialized Views (Precompute Expensive Aggregations)
```sql
CREATE MATERIALIZED VIEW order_stats AS
SELECT customer_id, COUNT(*) as orders, SUM(total) as revenue
FROM orders GROUP BY customer_id;

-- Refresh periodically (not on every write)
REFRESH MATERIALIZED VIEW CONCURRENTLY order_stats;

-- Saves: Eliminates expensive GROUP BY on every dashboard load
```

---

## Caching ROI

### When Caching Pays Off

```
Cache saves money when:
  (DB queries avoided × cost per query) > (Redis instance cost)

Example:
  10M requests/month, 85% cache hit → 8.5M queries avoided
  DB instance saved: db.t4g.large → db.t4g.micro = $97/month saved
  Redis cost: cache.t4g.micro = $12.24/month
  NET SAVINGS: $84.76/month
```

### When Caching Costs More Than It Saves
- Cache hit ratio < 50% (too many misses)
- Write-heavy workload (constant cache invalidation)
- Working set too large for cache instance
- TTL < 10 seconds (almost every request misses)

### Cache TTL Guidelines

| Data Type | TTL | Rationale |
|-----------|-----|-----------|
| Feature flags | 30-60s | Fast propagation needed |
| User profile | 5-15 min | Infrequent changes |
| Product catalog | 1-24 hours | Batch updates |
| Static config | 1 hour | Rarely changes |
| CDN static assets | 1 year | Versioned URLs (hash-based) |

---

## Memory Leak Detection

**Real case:** 4 lines of code caused **$12,000/month** in AWS costs from OOM restarts.

### Common Leak Patterns
```javascript
// LEAK: Event listeners never cleaned up
class UserService {
  constructor() {
    eventBus.on('userUpdate', this.handleUpdate);  // Never removed!
  }
  // Fix: Remove listener in destroy/cleanup
  destroy() { eventBus.off('userUpdate', this.handleUpdate); }
}

// LEAK: Closures holding large objects
function processData(hugeArray) {
  return function getStats() {
    return hugeArray.length;  // Holds entire array in memory forever
  };
}
// Fix: Extract only what you need
function processData(hugeArray) {
  const length = hugeArray.length;
  return function getStats() { return length; };
}

// LEAK: Growing collections without bounds
const cache = new Map();
function cacheResult(key, value) {
  cache.set(key, value);  // Never evicted!
}
// Fix: Use LRU cache with max size
import { LRUCache } from 'lru-cache';
const cache = new LRUCache({ max: 1000 });
```

### Detection
```bash
# Node.js heap snapshot
node --inspect app.js
# Open chrome://inspect → Take heap snapshot → Compare two snapshots

# In code: Monitor heap usage
setInterval(() => {
  const { heapUsed, heapTotal } = process.memoryUsage();
  if (heapUsed / heapTotal > 0.85) {
    console.warn(`Memory pressure: ${(heapUsed / 1024 / 1024).toFixed(0)}MB used`);
  }
}, 30000);
```

**Cost impact:** Memory leaks cause OOM restarts → cold start overhead → 20-40% higher cloud bills.

---

## Compression

### Response Compression
```typescript
import compression from 'compression';
app.use(compression({ threshold: 1024, level: 6 }));
// Reduces JSON responses by 70-90%
// 100KB response → 10-30KB
```

### Before Storage
```typescript
import zlib from 'zlib';

// Compress before S3 upload
const compressed = zlib.gzipSync(JSON.stringify(data));
await s3.putObject({
  Bucket: 'my-bucket', Key: 'data.json.gz',
  Body: compressed, ContentEncoding: 'gzip'
}).promise();
// JSON logs compress 80-90% → massive S3 savings
```

### Static Asset Compression
```javascript
// Vite/webpack: Generate .br and .gz files at build time
// vite.config.ts
import viteCompression from 'vite-plugin-compression';
export default {
  plugins: [
    viteCompression({ algorithm: 'brotliCompress' }), // Brotli: 20% better than gzip
    viteCompression({ algorithm: 'gzip' }),
  ]
};
```



---

## Reference file: `services-and-finops.md`

# Services & FinOps Reference

## Observability Cost Control

### The Problem
- Traces: 60-70% of observability costs
- Logs: 20-30% of observability costs
- Total market: $34.1B in 2026 — most of it wasted

### Platform Pricing (Monthly, Mid-Size Team)
| Platform | Cost | Pricing Model |
|----------|------|---------------|
| Datadog | $8,000+ | Per host + per GB + per metric (complex) |
| New Relic | $1,000-2,000 | Per user + per GB ingested |
| Grafana Cloud | $1,500 | Per signal volume + per user |
| Self-hosted Grafana + Prometheus | $200-500 | Infrastructure only |

### Log Sampling (Immediate Savings)
```typescript
import pino from 'pino';

const logger = pino({
  level: process.env.NODE_ENV === 'production' ? 'warn' : 'debug',
});

// Sample INFO-level logs in production
const SAMPLE_RATE = 0.1; // Log 10% of info events
function infoSampled(msg: string, data?: object) {
  if (Math.random() < SAMPLE_RATE) logger.info(data, msg);
}

// Always log errors and warnings (no sampling)
logger.error({ err, traceId }, 'Payment failed');
logger.warn({ userId }, 'Rate limit approaching');

// Sample info-level
infoSampled('Request completed', { path: req.path, duration: ms });
```
**Saves:** 90% log volume reduction while keeping all errors.

### Trace Sampling
```typescript
// Tail sampling: Keep 100% of errors + slow requests, sample the rest
const tracer = require('dd-trace').init({
  sampleRate: 0.1,  // Send 10% of normal traces
  // But always send error traces (configured in Datadog agent)
});
```
**Saves:** 70-80% on trace costs while keeping all interesting traces.

### High-Cardinality Metric Pitfalls
```typescript
// BAD: Creates millions of time series ($$$$)
counter.inc({ user_id: userId, request_id: requestId });

// GOOD: Aggregate by meaningful dimensions only
counter.inc({ endpoint: '/api/users', method: 'GET', status: '200' });
```
**Rule:** Never put user IDs, request IDs, timestamps, or UUIDs in metric labels.

### Retention Policies
| Log Type | Retention | Rationale |
|----------|----------|-----------|
| Application errors | 90 days | Debugging, postmortems |
| Access logs | 30 days | Security review period |
| Debug logs | 7 days | Short-term troubleshooting |
| Health check logs | 1 day | Almost never needed |
| CI/CD logs | 14 days | Build debugging |

---

## Auth Provider Economics

### Pricing Comparison (2026)

| Provider | Free Tier | Paid | SAML SSO |
|----------|----------|------|----------|
| Clerk | 10K MAUs | $0.02/MAU | $99/month |
| Auth0 | 7.5K MAUs | $240/month (3K MAUs) | $1,500/month |
| Supabase Auth | 50K MAUs | Included in Pro ($25) | Included |
| Keycloak | Unlimited | Free (self-host) | Free |
| Firebase Auth | 50K MAUs | Free (phone auth costs) | Not available |

### Cost at Scale
```
10,000 MAUs:
  Clerk: Free
  Auth0: $240/month
  Supabase: $25/month (included in Pro)
  Firebase: Free

100,000 MAUs:
  Clerk: $1,800/month (90K × $0.02)
  Auth0: $1,500+/month (Enterprise tier required)
  Supabase: $25/month (still included!)
  Firebase: Free (but limited features)

1,000,000 MAUs:
  Clerk: $19,800/month
  Auth0: Custom pricing ($$$$)
  Supabase: $25/month (yes, really)
  Self-hosted Keycloak: $50-200/month (infrastructure only)
```

**Rule:** Supabase Auth is cheapest at scale if you use Supabase. Self-hosted Keycloak for maximum control. Clerk for best DX at moderate scale.

---

## Search Service Costs

### Pricing (250K Records, 1M Searches/Month)
| Service | Monthly Cost | Self-Hostable |
|---------|-------------|---------------|
| Algolia | $500+ | No |
| Meilisearch Cloud | $59 | Yes (free) |
| Typesense Cloud | $60 | Yes (free) |
| Elasticsearch (AWS) | $200+ | Yes |
| Self-hosted Meilisearch | $15-30 (server) | Yes |

**Rule:** Start with Meilisearch (free self-hosted or $59 cloud). Only use Algolia if you need their specific features (AI recommendations, crawling).

---

## Email Service Costs

### Pricing (100K Emails/Month)
| Service | Cost | Notes |
|---------|------|-------|
| AWS SES | $10 | Cheapest, requires setup |
| Resend | $20 | Great DX, React Email |
| Postmark | $50 | Best deliverability |
| SendGrid | $20-50 | Established, complex pricing |

**Rule:** AWS SES for cost-sensitive. Resend for developer experience. Postmark for transactional email deliverability.

---

## FinOps Practices

### Cost Allocation Tags (Foundation)
```bash
# Tag ALL resources — untagged = unaccountable
aws ec2 create-tags --resources i-1234567890 --tags \
  Key=Environment,Value=production \
  Key=Team,Value=backend \
  Key=CostCenter,Value=engineering \
  Key=Service,Value=api-server
```

**Required tags:**
| Tag | Purpose | Example |
|-----|---------|---------|
| Environment | Filter prod vs dev costs | production, staging, dev |
| Team | Accountability | backend, frontend, data |
| Service | Granular attribution | api-server, worker, cron |
| CostCenter | Finance allocation | engineering, marketing |

### Budget Alerts
```bash
# AWS Budget with alert at 80% and 100%
aws budgets create-budget --account-id 123456789 --budget '{
  "BudgetName": "Monthly-Total",
  "BudgetLimit": { "Amount": "2000", "Unit": "USD" },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}' --notifications-with-subscribers '[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [{ "SubscriptionType": "EMAIL", "Address": "team@company.com" }]
  }
]'
```

### Unit Economics Tracking
```typescript
// Track cost per business metric
const metrics = {
  totalMonthlyCost: 2033,          // From AWS Cost Explorer
  monthlyActiveUsers: 50000,
  monthlyOrders: 100000,
  monthlyApiRequests: 10_000_000,
};

const unitEconomics = {
  costPerUser: metrics.totalMonthlyCost / metrics.monthlyActiveUsers,        // $0.041
  costPerOrder: metrics.totalMonthlyCost / metrics.monthlyOrders,            // $0.020
  costPerRequest: metrics.totalMonthlyCost / metrics.monthlyApiRequests,     // $0.0002
  costPerThousandRequests: (metrics.totalMonthlyCost / metrics.monthlyApiRequests) * 1000, // $0.20
};

// Alert if unit cost increases >20%
if (unitEconomics.costPerUser > previousMonth.costPerUser * 1.2) {
  alert('Cost per user increased >20% — investigate');
}
```

### Monthly Cost Review Checklist
- [ ] Review Cost Explorer for top 5 cost increases
- [ ] Check for untagged resources
- [ ] Identify idle/unused resources (0% CPU, no traffic)
- [ ] Review reserved capacity utilization (unused RIs = waste)
- [ ] Check for cost anomalies (unexpected spikes)
- [ ] Compare unit economics to previous month
- [ ] Review spot instance interruption rate (if using spot)
- [ ] Check data transfer costs by service

---

## Managed vs Self-Hosted Decision

### When Managed is Cheaper
- Team < 5 engineers (engineering time is expensive)
- Usage is low-moderate (managed pricing beats server costs)
- Need compliance/certifications (managed handles this)
- Ops expertise is limited

### When Self-Hosted is Cheaper
- Scale exceeds managed plan limits (1M+ MAUs for auth, 1M+ searches)
- You have ops/DevOps capability
- Data sovereignty requirements
- Predictable, stable workload

### Cost Crossover Points (Approximate)
```
Auth: Self-host at ~200K MAUs (Keycloak replaces $2K+/month Clerk/Auth0)
Search: Self-host at ~500K records (Meilisearch replaces $500+/month Algolia)
Database: Self-host at ~$500/month managed bill (but factor in ops time)
Redis: Self-host at ~$100/month managed bill
Email: Almost never self-host (SES at $0.10/1K is hard to beat)
```

---

## Cost Optimization Priority Matrix

| Action | Effort | Monthly Savings | Do First? |
|--------|--------|----------------|-----------|
| S3 Intelligent-Tiering | 5 min | $30-200 | Yes |
| Log retention policies | 10 min | $10-50 | Yes |
| Fix N+1 queries | 1-2 hours | $50-150 | Yes |
| WebP/AVIF images | 2-4 hours | $50-200 | Yes |
| VPC Endpoints | 1 hour | $50-300 | Yes |
| Lambda memory tuning | 1-2 hours | $20-100 | Yes |
| Bundle tree-shaking | 2-4 hours | $50-200 | Yes |
| Redis caching layer | 1-2 days | $50-300 | If read-heavy |
| Container right-sizing | 2-4 hours | $30-200 | If K8s |
| Reserved/Savings Plans | 1 hour | $200-1000 | If stable workload |
| Self-host auth/search | 1-2 weeks | $100-500 | At scale only |
| Trace sampling | 1 hour | $50-500 | If using Datadog/NR |
