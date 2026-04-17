# API Security Lab

A deliberately vulnerable REST API for learning API security with Postman.
**Local use only. Never deploy this.**

---

## Quick Start

```bash
cd api-security-lab
npm install
npm start
# Server runs on http://localhost:3000
```

Then in VS Code Postman extension:
1. Import `postman/API-Security-Lab.postman_collection.json`
2. Import `postman/API-Security-Lab.postman_environment.json`
3. Select the **"API Security Lab — Local"** environment
4. Run **SETUP — Get Tokens** first (populates auth tokens)
5. Work through each vulnerability folder in order

---

## Seed Users

| User  | Email             | Password    | Role  |
|-------|-------------------|-------------|-------|
| Alice | alice@lab.local   | Password1!  | admin |
| Bob   | bob@lab.local     | Password2!  | user  |
| Carol | carol@lab.local   | Password3!  | user  |

---

## Vulnerabilities Covered

| ID       | Name                        | Endpoint                    | OWASP API Top 10  |
|----------|-----------------------------|-----------------------------|-------------------|
| VULN-01  | Weak JWT secret             | POST /api/auth/login        | API2 Broken Auth  |
| VULN-02  | No token expiry             | All authenticated routes    | API2 Broken Auth  |
| VULN-03  | IDOR / BOLA                 | GET /api/users/:id          | API1 BOLA         |
| VULN-04  | Excessive data exposure     | GET /api/users/me           | API3 Excess Data  |
| VULN-05  | Mass assignment             | POST /api/auth/register     | API6 Mass Assign  |
| VULN-06  | BOLA on write/delete        | PUT/DELETE /api/users/:id   | API1 BOLA         |
| VULN-07  | Broken function-level auth  | GET /api/admin/users        | API5 BFLA         |
| VULN-08  | No rate limiting            | POST /api/auth/login        | API4 Rate Limit   |
| VULN-09  | Verbose errors              | GET /api/admin/debug        | API8 Misconfig    |
| VULN-10  | Missing security headers    | All routes                  | API8 Misconfig    |
| VULN-11  | Reflected input             | GET /api/products/search    | API8 Misconfig    |
| VULN-12  | No input validation         | POST /api/auth/register     | API6 Mass Assign  |

---

## Learning Path

### Step 1 — Explore (no auth)
- `GET /api/products` — what's public?
- `GET /api/admin/debug` — what's accidentally public?

### Step 2 — Authenticate
- Run the SETUP folder to get tokens for Alice and Bob

### Step 3 — Exploit each vulnerability
- Work through each folder in the collection
- Read the `[EXPLOIT]` and `[FINDING]` test messages in Postman's Test Results tab

### Step 4 — Fix it
- After exploiting each vuln, look at the `Fix:` comment in `server.js`
- Try implementing the fix and re-run the test to confirm it's patched

### Step 5 — Verify the fix
- Each Postman test is written so that a **fixed** server will make the test pass
- A **vulnerable** server will show `[FINDING]` or `[EXPLOIT]` labels as passing

---

## Recommended Fix Exercises

1. **VULN-01**: Replace `'secret123'` with `process.env.JWT_SECRET` and generate a strong key
2. **VULN-02**: Add `{ expiresIn: '1h' }` to `jwt.sign()`
3. **VULN-03**: In `GET /api/users/:id`, add `if (req.params.id !== req.user.id && req.user.role !== 'admin')`
4. **VULN-04**: Create a `sanitizeUser()` helper that returns only `{ id, name, email, role }`
5. **VULN-05**: Remove `role` from `req.body` in register; hardcode `role: 'user'`
6. **VULN-07**: Replace `req.headers['x-admin'] === 'true'` with `req.user.role === 'admin'`
7. **VULN-08**: Install and apply `express-rate-limit` to `/api/auth/login`
8. **VULN-10**: Install `helmet` and add `app.use(helmet())` near the top

---

## API Reference

```
POST   /api/auth/register       Register new user
POST   /api/auth/login          Login, get JWT

GET    /api/users/me            Own profile (auth required)
GET    /api/users/:id           Any user profile (auth required) [IDOR]
PUT    /api/users/:id           Update user [Mass Assignment]
DELETE /api/users/:id           Delete user [BOLA]

GET    /api/admin/users         All users — broken auth check [BFLA]
GET    /api/admin/debug         Full debug dump — no auth [Info Disclosure]

GET    /api/products            Public product list
GET    /api/products/search?q=  Search products [Reflected Input]
POST   /api/products            Create product (auth, no role check)

POST   /api/orders              Place order [No quantity validation]
GET    /api/orders/:id          Get order [IDOR]
```
