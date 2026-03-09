export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider
node -v
npm -v

netlify deploy --prod --site 6df47b6f-6792-4a74-8bb0-e2f4c41d2651

git add .
git commit -m 'netlify deploy --prod'
git push