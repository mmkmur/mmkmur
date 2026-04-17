const express = require('express');
const session = require('express-session');
const msal = require('@azure/msal-node');
const axios = require('axios');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;

// MSAL Configuration
const msalConfig = {
    auth: {
        clientId: 'fbf67495-bb1d-4091-a218-7948d6aa3309',
        clientSecret: process.env.CLIENT_SECRET, // Set CLIENT_SECRET as an environment variable
        authority: 'https://login.microsoftonline.com/7208f19e-1d16-4dcd-8da1-05d4890df033'
    },
    system: {
        loggerOptions: {
            loggerCallback(logLevel, message, containsPii) {
                console.log(message);
            },
            piiLoggingEnabled: false,
            logLevel: msal.LogLevel.Info,
        }
    }
};

// Create MSAL instance
const cca = new msal.ConfidentialClientApplication(msalConfig);

// Middleware
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static('public'));
app.set('view engine', 'ejs');

// Session configuration
app.use(session({
    secret: 'your-session-secret-change-this-in-production',
    resave: false,
    saveUninitialized: false,
    cookie: { secure: false, maxAge: 1000 * 60 * 60 * 24 } // 24 hours
}));

// In-memory storage for demo (replace with database in production)
let users = {};
let invitations = [];

// Helper function to check if user is authenticated
function isAuthenticated(req, res, next) {
    if (req.session.user) {
        next();
    } else {
        res.redirect('/login');
    }
}

// Routes

// Home page
app.get('/', (req, res) => {
    if (req.session.user) {
        res.redirect('/dashboard');
    } else {
        res.render('index', { user: null });
    }
});

// Login page
app.get('/login', (req, res) => {
    if (req.session.user) {
        res.redirect('/dashboard');
    } else {
        res.render('login', { error: null });
    }
});

// Microsoft Login
app.get('/auth/microsoft', async (req, res) => {
    const authUrlParameters = {
        scopes: ['user.read'],
        redirectUri: 'https://entraid-b2b-poc.azurewebsites.net/auth/callback',
        prompt: 'select_account'
    };

    try {
        const authUrl = await cca.getAuthCodeUrl(authUrlParameters);
        res.redirect(authUrl);
    } catch (error) {
        console.error('Error generating auth URL:', error);
        res.redirect('/login?error=auth_failed');
    }
});

// Auth callback
app.get('/auth/callback', async (req, res) => {
    const tokenRequest = {
        code: req.query.code,
        scopes: ['user.read'],
        redirectUri: 'https://entraid-b2b-poc.azurewebsites.net/auth/callback',
    };

    try {
        const response = await cca.acquireTokenByCode(tokenRequest);
        
        // Get user info from Microsoft Graph
        const userInfo = await axios.get('https://graph.microsoft.com/v1.0/me', {
            headers: {
                'Authorization': `Bearer ${response.accessToken}`
            }
        });

        // Store user in session
        req.session.user = {
            id: userInfo.data.id,
            email: userInfo.data.mail || userInfo.data.userPrincipalName,
            name: userInfo.data.displayName,
            accessToken: response.accessToken
        };

        // Store user in our "database"
        users[userInfo.data.id] = req.session.user;

        res.redirect('/dashboard');
    } catch (error) {
        console.error('Token acquisition failed:', error);
        res.redirect('/login?error=callback_failed');
    }
});

// Dashboard
app.get('/dashboard', isAuthenticated, (req, res) => {
    res.render('dashboard', { 
        user: req.session.user,
        invitations: invitations.filter(inv => inv.invitedBy === req.session.user.id)
    });
});

// Invite user page
app.get('/invite', isAuthenticated, (req, res) => {
    res.render('invite', { user: req.session.user, message: null });
});

// Send B2B invitation
app.post('/send-invitation', isAuthenticated, async (req, res) => {
    const { email, displayName, message } = req.body;
    
    try {
        // Prepare invitation data
        const invitationData = {
            invitedUserEmailAddress: email,
            invitedUserDisplayName: displayName,
            inviteRedirectUrl: 'https://entraid-b2b-poc.azurewebsites.net/',
            sendInvitationMessage: true,
            customizedMessageBody: message || 'You have been invited to access our application.'
        };

        // Send invitation via Microsoft Graph
        const response = await axios.post(
            'https://graph.microsoft.com/v1.0/invitations',
            invitationData,
            {
                headers: {
                    'Authorization': `Bearer ${req.session.user.accessToken}`,
                    'Content-Type': 'application/json'
                }
            }
        );

        // Store invitation record
        const invitation = {
            id: response.data.id,
            email: email,
            displayName: displayName,
            status: 'Pending',
            invitedBy: req.session.user.id,
            invitedByName: req.session.user.name,
            inviteRedeemUrl: response.data.inviteRedeemUrl,
            createdAt: new Date()
        };
        
        invitations.push(invitation);

        res.render('invite', { 
            user: req.session.user, 
            message: `Invitation sent successfully to ${email}! They will receive an email with instructions to access the application.`
        });

    } catch (error) {
        console.error('Error sending invitation:', error.response?.data || error.message);
        res.render('invite', { 
            user: req.session.user, 
            message: `Error sending invitation: ${error.response?.data?.error?.message || error.message}`
        });
    }
});

// Users list (admin view)
app.get('/users', isAuthenticated, (req, res) => {
    res.render('users', { 
        user: req.session.user,
        users: Object.values(users),
        invitations: invitations
    });
});

// Logout
app.get('/logout', (req, res) => {
    req.session.destroy((err) => {
        if (err) {
            console.error('Error destroying session:', err);
        }
        res.redirect('/');
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).send('Something broke!');
});

// 404 handler
app.use((req, res) => {
    res.status(404).render('404', { user: req.session.user || null });
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Local: http://localhost:${PORT}`);
    console.log(`Azure: https://entraid-b2b-poc.azurewebsites.net`);
});