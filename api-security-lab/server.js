/**
 * API Security Lab — Deliberately Vulnerable REST API
 *
 * Each vulnerability is clearly labeled with:
 *   [VULN-XX] name — what is wrong and why
 *
 * This is for LOCAL LEARNING ONLY. Never deploy this to production.
 *
 * Vulnerabilities included:
 *   VULN-01  Weak JWT secret (Broken Authentication)
 *   VULN-02  No token expiry enforcement
 *   VULN-03  IDOR / BOLA on GET /api/users/:id
 *   VULN-04  Excessive data exposure (password hash in response)
 *   VULN-05  Mass assignment — role escalation via PUT /api/users/:id
 *   VULN-06  Broken Object Level Auth on DELETE /api/users/:id
 *   VULN-07  Broken Function Level Auth — admin check via header
 *   VULN-08  No rate limiting on /api/auth/login (brute force)
 *   VULN-09  Verbose errors leaking internals
 *   VULN-10  Missing security headers (X-Content-Type, X-Frame-Options, etc.)
 *   VULN-11  Reflected input in search (potential XSS in JSON API)
 *   VULN-12  No input validation on register (no email format check, etc.)
 */

const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = 3000;

app.use(express.json());

// ─────────────────────────────────────────────
// [VULN-01] Weak JWT secret — easily brute-forced
// Fix: use a long random secret from env variable
// ─────────────────────────────────────────────
const JWT_SECRET = 'secret123';

// ─────────────────────────────────────────────
// [VULN-10] No security headers set anywhere
// Fix: use helmet middleware
// ─────────────────────────────────────────────

// ── In-memory data store (no database needed) ──
const db = {
    users: [
        {
            id: 'u-001',
            name: 'Alice Admin',
            email: 'alice@lab.local',
            password: bcrypt.hashSync('Password1!', 8),
            role: 'admin',
            ssn: '123-45-6789',          // sensitive field — should never be returned
            creditCard: '4111-1111-1111-1111'
        },
        {
            id: 'u-002',
            name: 'Bob User',
            email: 'bob@lab.local',
            password: bcrypt.hashSync('Password2!', 8),
            role: 'user',
            ssn: '987-65-4321',
            creditCard: '4222-2222-2222-2222'
        },
        {
            id: 'u-003',
            name: 'Carol User',
            email: 'carol@lab.local',
            password: bcrypt.hashSync('Password3!', 8),
            role: 'user',
            ssn: '555-55-5555',
            creditCard: '4333-3333-3333-3333'
        }
    ],
    products: [
        { id: 'p-001', name: 'Widget A', price: 9.99, stock: 100 },
        { id: 'p-002', name: 'Gadget B', price: 49.99, stock: 25 },
        { id: 'p-003', name: 'Doohickey C', price: 4.99, stock: 200 },
        { id: 'p-004', name: 'Secret Product', price: 999.99, stock: 1, internal: true }
    ],
    orders: []
};

// ── Helpers ──

function findUser(id) {
    return db.users.find(u => u.id === id);
}

function findUserByEmail(email) {
    return db.users.find(u => u.email === email);
}

// ─────────────────────────────────────────────
// Auth Middleware
// ─────────────────────────────────────────────
function requireAuth(req, res, next) {
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Missing or malformed Authorization header' });
    }

    const token = authHeader.split(' ')[1];
    try {
        // [VULN-02] No expiry check — expired tokens are still accepted if verify() passes
        // Fix: ensure token was generated with expiresIn and validate exp claim
        const decoded = jwt.verify(token, JWT_SECRET);
        req.user = decoded;
        next();
    } catch (err) {
        // [VULN-09] Leaking internal error detail
        // Fix: return a generic message, log internally
        return res.status(401).json({ error: 'Invalid token', detail: err.message });
    }
}

// ─────────────────────────────────────────────
// ══ AUTH ROUTES ══
// ─────────────────────────────────────────────

// POST /api/auth/register
// [VULN-12] No input validation — accepts any email format, empty fields, etc.
app.post('/api/auth/register', (req, res) => {
    const { name, email, password, role } = req.body;

    if (!name || !email || !password) {
        return res.status(400).json({ error: 'name, email and password are required' });
    }

    if (findUserByEmail(email)) {
        return res.status(409).json({ error: 'Email already registered' });
    }

    const newUser = {
        id: uuidv4(),
        name,
        email,
        password: bcrypt.hashSync(password, 8),
        // [VULN-05] Mass assignment — client can set their own role to 'admin'
        // Fix: never accept role from the request body; hardcode 'user'
        role: role || 'user',
        ssn: '',
        creditCard: ''
    };

    db.users.push(newUser);

    // [VULN-04] Returning password hash in register response
    // Fix: return only { id, name, email, role }
    res.status(201).json({ message: 'Registered', user: newUser });
});

// POST /api/auth/login
// [VULN-08] No rate limiting — brute force login is possible
app.post('/api/auth/login', (req, res) => {
    const { email, password } = req.body;

    const user = findUserByEmail(email);
    if (!user || !bcrypt.compareSync(password, user.password)) {
        // [VULN-09] Generic-ish message is good here, but see other routes for worse leakage
        return res.status(401).json({ error: 'Invalid credentials' });
    }

    // [VULN-01] Signed with weak secret, [VULN-02] No expiresIn set
    // Fix: jwt.sign({ id, role }, process.env.JWT_SECRET, { expiresIn: '1h' })
    const token = jwt.sign({ id: user.id, email: user.email, role: user.role }, JWT_SECRET);

    res.json({
        token,
        user: { id: user.id, name: user.name, email: user.email, role: user.role }
    });
});

// ─────────────────────────────────────────────
// ══ USER ROUTES ══
// ─────────────────────────────────────────────

// GET /api/users/me — own profile
app.get('/api/users/me', requireAuth, (req, res) => {
    const user = findUser(req.user.id);
    if (!user) return res.status(404).json({ error: 'User not found' });

    // [VULN-04] Excessive data exposure — returning ssn, creditCard, password hash
    // Fix: return only { id, name, email, role }
    res.json(user);
});

// GET /api/users/:id — get any user by ID
// [VULN-03] IDOR / BOLA — any authenticated user can read any other user's data
// Fix: check req.user.id === req.params.id (or admin role)
app.get('/api/users/:id', requireAuth, (req, res) => {
    const user = findUser(req.params.id);
    if (!user) return res.status(404).json({ error: 'User not found' });

    // [VULN-04] Again returning all fields including SSN and credit card
    res.json(user);
});

// PUT /api/users/:id — update user
// [VULN-05] Mass assignment + [VULN-06] BOLA on write
// Fix: only allow updating name/password for own account; strip role from input
app.put('/api/users/:id', requireAuth, (req, res) => {
    const user = findUser(req.params.id);
    if (!user) return res.status(404).json({ error: 'User not found' });

    // No ownership check — any user can update any other user's record
    // No field allowlist — attacker can change role to 'admin'
    Object.assign(user, req.body);

    res.json({ message: 'User updated', user });
});

// DELETE /api/users/:id
// [VULN-06] Broken Object Level Auth — any authenticated user can delete any account
// Fix: check ownership or admin role
app.delete('/api/users/:id', requireAuth, (req, res) => {
    const index = db.users.findIndex(u => u.id === req.params.id);
    if (index === -1) return res.status(404).json({ error: 'User not found' });

    const deleted = db.users.splice(index, 1)[0];
    res.json({ message: 'User deleted', id: deleted.id });
});

// ─────────────────────────────────────────────
// ══ ADMIN ROUTES ══
// ─────────────────────────────────────────────

// GET /api/admin/users — list all users (admin only)
// [VULN-07] Broken Function Level Auth — admin check reads a header, not the JWT role
// Any user can pass X-Admin: true and get the full user list
// Fix: check req.user.role === 'admin' from the verified JWT
app.get('/api/admin/users', requireAuth, (req, res) => {
    const isAdmin = req.headers['x-admin'] === 'true';
    if (!isAdmin) {
        return res.status(403).json({ error: 'Admins only' });
    }
    // Returns ALL fields including SSN, credit cards
    res.json({ users: db.users });
});

// GET /api/admin/debug — exposes internal state
// [VULN-09] Debug endpoint should never exist in production
app.get('/api/admin/debug', (req, res) => {
    res.json({
        jwtSecret: JWT_SECRET,
        userCount: db.users.length,
        users: db.users,
        env: process.env
    });
});

// ─────────────────────────────────────────────
// ══ PRODUCT ROUTES ══
// ─────────────────────────────────────────────

// GET /api/products — public product list
// Returns internal:true products to everyone
app.get('/api/products', (req, res) => {
    res.json({ products: db.products });
});

// GET /api/products/search?q=
// [VULN-11] Reflected user input — q param reflected back in response without sanitization
// In a JSON API this won't cause browser XSS, but it's still a bad pattern
// and can be exploited via log injection or downstream parsers
app.get('/api/products/search', (req, res) => {
    const query = req.query.q || '';
    const results = db.products.filter(p =>
        p.name.toLowerCase().includes(query.toLowerCase())
    );
    // Reflecting raw input back
    res.json({ query, results });
});

// POST /api/products — create product (auth required, but no role check)
// [VULN-07] Any authenticated user can create products, not just admins
app.post('/api/products', requireAuth, (req, res) => {
    const { name, price, stock } = req.body;
    const product = { id: uuidv4(), name, price, stock };
    db.products.push(product);
    res.status(201).json({ message: 'Product created', product });
});

// ─────────────────────────────────────────────
// ══ ORDER ROUTES ══
// ─────────────────────────────────────────────

// POST /api/orders — place an order
app.post('/api/orders', requireAuth, (req, res) => {
    const { productId, quantity } = req.body;
    const product = db.products.find(p => p.id === productId);
    if (!product) return res.status(404).json({ error: 'Product not found' });

    // No negative quantity check — can order -100 to inflate stock
    const order = {
        id: uuidv4(),
        userId: req.user.id,
        productId,
        quantity,
        total: product.price * quantity,
        createdAt: new Date()
    };

    product.stock -= quantity; // No bounds check
    db.orders.push(order);

    res.status(201).json({ message: 'Order placed', order });
});

// GET /api/orders/:id — get order
// [VULN-03] IDOR — any authenticated user can view any order
app.get('/api/orders/:id', requireAuth, (req, res) => {
    const order = db.orders.find(o => o.id === req.params.id);
    if (!order) return res.status(404).json({ error: 'Order not found' });
    res.json(order);
});

// ─────────────────────────────────────────────
// Error handler
// [VULN-09] Leaks full stack trace
// Fix: log internally, return generic message
// ─────────────────────────────────────────────
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({
        error: 'Internal Server Error',
        message: err.message,
        stack: err.stack   // NEVER do this in production
    });
});

// 404
app.use((req, res) => {
    res.status(404).json({ error: `Route ${req.method} ${req.path} not found` });
});

app.listen(PORT, () => {
    console.log(`\n API Security Lab running on http://localhost:${PORT}`);
    console.log(' This server is deliberately vulnerable — local use only.\n');
    console.log(' Routes:');
    console.log('   POST /api/auth/register');
    console.log('   POST /api/auth/login');
    console.log('   GET  /api/users/me');
    console.log('   GET  /api/users/:id         [VULN-03 IDOR]');
    console.log('   PUT  /api/users/:id         [VULN-05 Mass Assignment]');
    console.log('   DELETE /api/users/:id       [VULN-06 BOLA]');
    console.log('   GET  /api/admin/users       [VULN-07 Broken Auth]');
    console.log('   GET  /api/admin/debug       [VULN-09 Info Disclosure]');
    console.log('   GET  /api/products');
    console.log('   GET  /api/products/search   [VULN-11 Reflected Input]');
    console.log('   POST /api/products');
    console.log('   POST /api/orders');
    console.log('   GET  /api/orders/:id        [VULN-03 IDOR]');
});
