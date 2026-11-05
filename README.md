# Netlify React App — Deploy & Custom Domain Guide

## Install Netlify CLI globally

```bash
npm install -g netlify-cli
```

## Login to Netlify

Load NVM and configure Node:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider
node -v
npm -v
```

Then log in:

```bash
netlify login
```

> If you're already logged in via Netlify config on your machine, you'll see a message confirming that.
>
> - Run `netlify status` for account details.
> - Run `netlify switch` to switch accounts.
> - Run `netlify help` to see all available commands.

## Initialize and deploy

Navigate to your project folder and initialize:

```bash
cd your-website-folder
netlify init
```

Follow the prompts to create a new site or connect an existing one.

## Deploy to production

```bash
netlify deploy --prod
```

### Full deploy command (with environment setup)

```bash
#netlify deploy
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider
node -v
npm -v
netlify deploy --prod
```

## Logout

```bash
netlify logout
```

---

## Initial state

- The system showed 248 npm packages looking for funding (view with `npm fund`).

---

## Deploy attempt log

### First attempt

```bash
netlify deploy
```

- CLI attempted to log into the Netlify account.
- Opened Safari to `https://app.netlify.com/authorize?response_type=ticket&ticket=1b8093b4a334c1643bace36afe654e4e`
- User had to log in through the browser.
- Console got stuck on "authentication in progress".
- User pressed `Ctrl+C` to cancel.

### Second attempt

```bash
netlify deploy
```

- Opened new auth URL: `https://app.netlify.com/authorize?response_type=ticket&ticket=c5e66cc6e0d776724b22a3d2dc5898a5`
- Since the user was already logged in, they only had to accept authentication for React upload permissions.
- Authentication successful: "You are now logged into your Netlify account!"
- CLI crashed when trying to select a team:
  - `Error: Netlify CLI has terminated unexpectedly`
  - `TypeError: Cannot read properties of undefined (reading 'value')`
  - The error suggested a possible CLI version issue.

### Third attempt (successful)

```bash
netlify deploy
```

- Created a new site:
  - **Team:** IGIRemakeTeam
  - **Site name:** ytembed
  - **Admin URL:** https://app.netlify.com/projects/ytembed
  - **Live URL:** https://ytembed.netlify.app
  - **Site ID:** `398ef3a2-276c-409c-9674-51fe1a4af309`
- Build process:
  - Ran `npm run build` (React build).
  - Showed ESLint warnings in `App.js`.
  - Successful build with production-ready files.
- Deployed draft version:
  - **Draft URL:** https://682a2ffbe227ee75ddb6d0fa--ytembed.netlify.app

### Production deploy

```bash
netlify deploy --prod
```

- Ran the build again (same warnings).
- Deployed to production:
  - **Production URL:** https://ytembed.netlify.app
  - **Unique deploy URL:** https://682a304d16d26dd1515e24ed--ytembed.netlify.app

### System information

- **OS:** macOS 11.7.10
- **CPU:** Intel Core i7-4870HQ
- **Node:** v22.15.1
- **npm:** 10.9.2
- **Netlify CLI:** 21.4.2
- **Browsers:** Chrome 136, Safari 16.6

### Authentication flow notes

1. First attempt required a full login in Safari.
2. Got stuck in the console after browser login.
3. Second attempt (after `Ctrl+C`) only required authorization approval.
4. After approval, the deployment process could continue.

The entire process resulted in a successfully deployed React application to Netlify — first as a draft version, then to production.

---

## Custom domain setup (Namecheap → Netlify)

### 1. Buy the domain

Bought `ytembed.xyz` on **Namecheap**.

### 2. Add the domain in Netlify

In Netlify: **Project → Domain management → Add a new domain**.

Netlify provides these DNS records (Netlify DNS nameservers):

```
dns1.p05.nsone.net
dns2.p05.nsone.net
dns3.p05.nsone.net
dns4.p05.nsone.net
```

### 3. Point Namecheap to Netlify DNS

In **Namecheap → Domain → Nameservers → Custom DNS**, add the four nameservers above.

### 4. Wait for propagation

Back in Netlify: **Domain management** → wait until the domain is found / verified.

### 5. Enable SSL

Click **Create SSL certificate** (Netlify provisions a free Let's Encrypt cert once DNS is verified).

**Done.** 🎉
