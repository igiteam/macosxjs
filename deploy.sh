#!/bin/bash
set -e

# Digital Ocean Spaces Folder Uploader
# Uses VS Code extension settings to upload entire folder

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider

echo "📦 Node: $(node -v) | npm: $(npm -v)"
echo ""

# ============================================
# Read VS Code Extension Settings
# ============================================

echo "🔍 Reading VS Code extension settings..."

# Try to find VS Code settings in common locations
VSCODE_SETTINGS=""

# macOS locations
if [ -f "$HOME/Library/Application Support/Code/User/settings.json" ]; then
    VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
    echo "   Found settings: $VSCODE_SETTINGS"
elif [ -f "$HOME/.config/Code/User/settings.json" ]; then
    VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
    echo "   Found settings: $VSCODE_SETTINGS"
elif [ -f "$HOME/AppData/Roaming/Code/User/settings.json" ]; then
    VSCODE_SETTINGS="$HOME/AppData/Roaming/Code/User/settings.json"
    echo "   Found settings: $VSCODE_SETTINGS"
fi

if [ ! -f "$VSCODE_SETTINGS" ]; then
    echo "❌ Could not find VS Code settings file"
    echo ""
    read -p "Do you want to enter credentials manually? (y/N): " MANUAL
    MANUAL=${MANUAL:-N}
    
    if [[ "$MANUAL" != "y" && "$MANUAL" != "Y" ]]; then
        exit 1
    fi
fi

# Function to get setting from JSON
get_setting() {
    local key="$1"
    local default="$2"
    
    if [ ! -f "$VSCODE_SETTINGS" ]; then
        echo "$default"
        return
    fi
    
    # Try Python first
    if command -v python3 &> /dev/null; then
        local value=$(python3 -c "
import json, sys, os
try:
    with open('$VSCODE_SETTINGS', 'r') as f:
        data = json.load(f)
    print(data.get('$key', '$default'))
except:
    print('$default')
" 2>/dev/null)
        echo "$value"
        return
    fi
    
    # Try jq
    if command -v jq &> /dev/null; then
        local value=$(jq -r ".\"$key\" // \"$default\"" "$VSCODE_SETTINGS" 2>/dev/null || echo "$default")
        echo "$value"
        return
    fi
    
    # Fallback to grep
    local value=$(grep -o "\"$key\":\s*\"[^\"]*\"" "$VSCODE_SETTINGS" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "$default")
    echo "$value"
}

# Read settings
if [ -f "$VSCODE_SETTINGS" ]; then
    ACCESS_KEY=$(get_setting "dospaces.accessKey" "")
    SECRET_KEY=$(get_setting "dospaces.secretKey" "")
    BUCKET=$(get_setting "dospaces.bucket" "")
    ENDPOINT=$(get_setting "dospaces.endpoint" "https://nyc3.digitaloceanspaces.com")
    REGION=$(get_setting "dospaces.region" "us-east-1")
    FOLDER=$(get_setting "dospaces.folder" "uploads")
    CDN_ENDPOINT=$(get_setting "dospaces.cdnEndpoint" "")
    API_TOKEN=$(get_setting "dospaces.apiToken" "")
    CDN_ID=$(get_setting "dospaces.cdnId" "")
else
    ACCESS_KEY=""
    SECRET_KEY=""
    BUCKET=""
    ENDPOINT="https://nyc3.digitaloceanspaces.com"
    REGION="us-east-1"
    FOLDER="uploads"
    CDN_ENDPOINT=""
    API_TOKEN=""
    CDN_ID=""
fi

# Validate settings or ask for manual input
if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ] || [ -z "$BUCKET" ]; then
    echo ""
    echo "⚠️  Missing Digital Ocean Spaces configuration"
    echo ""
    echo "📝 Please enter your credentials:"
    echo ""
    
    if [ -z "$ACCESS_KEY" ]; then
        read -p "Digital Ocean Access Key: " ACCESS_KEY
    else
        echo "Access Key: [already set]"
    fi
    
    if [ -z "$SECRET_KEY" ]; then
        read -p "Digital Ocean Secret Key: " SECRET_KEY
    else
        echo "Secret Key: [already set]"
    fi
    
    if [ -z "$BUCKET" ]; then
        read -p "Bucket Name: " BUCKET
    else
        echo "Bucket: $BUCKET"
    fi
    
    read -p "Endpoint [$ENDPOINT]: " INPUT_ENDPOINT
    ENDPOINT=${INPUT_ENDPOINT:-$ENDPOINT}
    
    read -p "Region [$REGION]: " INPUT_REGION
    REGION=${INPUT_REGION:-$REGION}
    
    read -p "Target Folder [$FOLDER]: " INPUT_FOLDER
    FOLDER=${INPUT_FOLDER:-$FOLDER}
    
    read -p "CDN Endpoint [$CDN_ENDPOINT]: " INPUT_CDN_ENDPOINT
    CDN_ENDPOINT=${INPUT_CDN_ENDPOINT:-$CDN_ENDPOINT}
    
    read -p "API Token [$API_TOKEN]: " INPUT_API_TOKEN
    API_TOKEN=${INPUT_API_TOKEN:-$API_TOKEN}
    
    read -p "CDN ID [$CDN_ID]: " INPUT_CDN_ID
    CDN_ID=${INPUT_CDN_ID:-$CDN_ID}
fi

echo ""
echo "✅ Configuration loaded:"
echo "   Bucket: $BUCKET"
echo "   Endpoint: $ENDPOINT"
echo "   Target Folder: $FOLDER"
echo "   Region: $REGION"
if [ -n "$CDN_ENDPOINT" ]; then
    echo "   CDN Endpoint: $CDN_ENDPOINT"
fi
if [ -n "$API_TOKEN" ]; then
    echo "   API Token: ✓ (set)"
fi
if [ -n "$CDN_ID" ]; then
    echo "   CDN ID: $CDN_ID"
fi
echo ""

# ============================================
# Create upload script
# ============================================

echo "📝 Creating upload script..."

UPLOAD_SCRIPT="upload_folder.js"

cat > "$UPLOAD_SCRIPT" << 'EOL'
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const fs = require('fs');
const path = require('path');
const https = require('https');

async function uploadFolder() {
    console.log('🚀 Starting folder upload to Digital Ocean Spaces...\n');

    // Configuration from environment/bash script
    const config = {
        accessKeyId: process.env.DO_ACCESS_KEY,
        secretAccessKey: process.env.DO_SECRET_KEY,
        endpoint: process.env.DO_ENDPOINT || 'https://nyc3.digitaloceanspaces.com',
        region: process.env.DO_REGION || 'us-east-1',
        bucket: process.env.DO_BUCKET,
        folder: process.env.DO_FOLDER || 'uploads',
        cdnEndpoint: process.env.DO_CDN_ENDPOINT || '',
        apiToken: process.env.DO_API_TOKEN || '',
        cdnId: process.env.DO_CDN_ID || ''
    };

    console.log('Configuration:');
    console.log(`- Bucket: ${config.bucket}`);
    console.log(`- Endpoint: ${config.endpoint}`);
    console.log(`- Folder: ${config.folder}`);
    console.log(`- Region: ${config.region}`);
    console.log(`- CDN Endpoint: ${config.cdnEndpoint || 'none'}`);
    console.log(`- CDN ID: ${config.cdnId || 'none'}`);
    console.log('');

    // Validate config
    if (!config.accessKeyId || !config.secretAccessKey || !config.bucket) {
        console.error('❌ Missing required configuration');
        console.error('   Please set DO_ACCESS_KEY, DO_SECRET_KEY, and DO_BUCKET environment variables');
        process.exit(1);
    }

    // Create S3 client
    const s3Client = new S3Client({
        endpoint: config.endpoint,
        forcePathStyle: false,
        region: config.region,
        credentials: {
            accessKeyId: config.accessKeyId,
            secretAccessKey: config.secretAccessKey
        }
    });

    // Get current directory
    const currentDir = process.cwd();
    console.log(`📁 Current directory: ${currentDir}\n`);

    // Collect all files
    const files = [];
    
    function collectFiles(dir, basePath = '') {
        const items = fs.readdirSync(dir);
        
        for (const item of items) {
            const fullPath = path.join(dir, item);
            const relativePath = basePath ? path.join(basePath, item) : item;
            
            // Skip hidden files and common directories
            if (item.startsWith('.') || item === 'node_modules' || item === '.git') {
                continue;
            }
            
            if (fs.statSync(fullPath).isDirectory()) {
                // Recursively collect files from subdirectories
                collectFiles(fullPath, relativePath);
            } else {
                files.push({
                    localPath: fullPath,
                    relativePath: relativePath,
                    key: config.folder ? `${config.folder}/${relativePath}` : relativePath
                });
            }
        }
    }

    collectFiles(currentDir);
    
    if (files.length === 0) {
        console.log('❌ No files found in current directory');
        process.exit(1);
    }

    console.log(`📊 Found ${files.length} files to upload:\n`);
    
    let uploadedCount = 0;
    const failedFiles = [];
    const uploadedFiles = [];

    // Upload files sequentially
    for (let i = 0; i < files.length; i++) {
        const file = files[i];
        const fileSize = fs.statSync(file.localPath).size;
        const fileSizeMB = fileSize > 1024 * 1024 ? (fileSize / (1024 * 1024)).toFixed(2) + ' MB' : 
                          fileSize > 1024 ? (fileSize / 1024).toFixed(2) + ' KB' : 
                          fileSize + ' bytes';
        
        try {
            process.stdout.write(`[${i + 1}/${files.length}] 📤 ${file.relativePath} (${fileSizeMB})... `);
            
            // Read file content
            const fileContent = fs.readFileSync(file.localPath);
            
            // Determine content type based on file extension
            const ext = path.extname(file.localPath).toLowerCase();
            let contentType = 'application/octet-stream';
            
            if (ext === '.html' || ext === '.htm') contentType = 'text/html';
            else if (ext === '.css') contentType = 'text/css';
            else if (ext === '.js') contentType = 'application/javascript';
            else if (ext === '.json') contentType = 'application/json';
            else if (ext === '.png') contentType = 'image/png';
            else if (ext === '.jpg' || ext === '.jpeg') contentType = 'image/jpeg';
            else if (ext === '.gif') contentType = 'image/gif';
            else if (ext === '.svg') contentType = 'image/svg+xml';
            else if (ext === '.txt' || ext === '.md') contentType = 'text/plain';
            else if (ext === '.pdf') contentType = 'application/pdf';
            else if (ext === '.zip') contentType = 'application/zip';
            else if (ext === '.ico') contentType = 'image/x-icon';
            else if (ext === '.webp') contentType = 'image/webp';
            else if (ext === '.mp4') contentType = 'video/mp4';
            else if (ext === '.mp3') contentType = 'audio/mpeg';
            else if (ext === '.woff') contentType = 'font/woff';
            else if (ext === '.woff2') contentType = 'font/woff2';
            else if (ext === '.ttf') contentType = 'font/ttf';
            
            // Add cache-busting timestamp
            const timestamp = Date.now();
            
            const params = {
                Bucket: config.bucket,
                Key: file.key,
                Body: fileContent,
                ContentType: contentType,
                ACL: 'public-read',
                Metadata: {
                    'uploaded-from': 'folder-upload-script',
                    'original-path': file.relativePath,
                    'x-amz-meta-version': timestamp.toString(),
                    'x-amz-meta-last-modified': new Date().toISOString()
                }
            };
            
            await s3Client.send(new PutObjectCommand(params));
            
            uploadedCount++;
            uploadedFiles.push(file.key);
            
            console.log(`✅`);
            
        } catch (error) {
            console.log(`❌ Failed: ${error.message}`);
            failedFiles.push({ file: file.relativePath, error: error.message });
        }
    }

    console.log(`\n📊 Upload Summary:`);
    console.log(`   ✅ Successfully uploaded: ${uploadedCount}/${files.length}`);
    console.log(`   ❌ Failed: ${failedFiles.length}`);
    
    if (uploadedFiles.length > 0) {
        // Construct base URL
        const spaceUrl = config.endpoint.replace('https://', `https://${config.bucket}.`);
        const baseUrl = config.cdnEndpoint ? config.cdnEndpoint : `${spaceUrl}/${config.folder}`;
        
        console.log(`\n🌐 Files available at: ${baseUrl}/`);
        console.log(`   Example: ${baseUrl}/${uploadedFiles[0]}`);
        
        // Write URLs to file
        fs.writeFileSync('uploaded_urls.txt', 
            `Upload completed: ${new Date().toISOString()}\n` +
            `Base URL: ${baseUrl}/\n` +
            `Files uploaded: ${uploadedFiles.length}\n\n` +
            uploadedFiles.map(f => `${baseUrl}/${f}`).join('\n')
        );
        console.log(`\n📄 URLs saved to: uploaded_urls.txt`);
    }

    // CDN Purge if configured
    if (config.apiToken && config.cdnId && uploadedFiles.length > 0) {
        console.log('\n🔄 Purging CDN cache...');
        
        try {
            const purgeBody = JSON.stringify({ files: uploadedFiles });
            
            await new Promise((resolve, reject) => {
                const req = https.request({
                    method: "DELETE",
                    hostname: "api.digitalocean.com",
                    path: `/v2/cdn/endpoints/${config.cdnId}/cache`,
                    headers: {
                        "Authorization": `Bearer ${config.apiToken}`,
                        "Content-Type": "application/json",
                        "Content-Length": Buffer.byteLength(purgeBody).toString()
                    }
                }, (res) => {
                    let responseData = '';
                    res.on('data', (chunk) => {
                        responseData += chunk;
                    });
                    
                    res.on('end', () => {
                        if (res.statusCode === 204 || res.statusCode === 200) {
                            console.log('✅ CDN cache purged successfully');
                            resolve(true);
                        } else {
                            console.log(`⚠️ CDN purge returned status ${res.statusCode}: ${responseData}`);
                            resolve(false);
                        }
                    });
                });
                
                req.on('error', (error) => {
                    console.log(`⚠️ CDN purge error: ${error.message}`);
                    resolve(false);
                });
                
                req.write(purgeBody);
                req.end();
            });
        } catch (error) {
            console.log(`⚠️ CDN purge failed: ${error.message}`);
        }
    }
    
    if (failedFiles.length > 0) {
        console.log('\n❌ Failed files:');
        failedFiles.forEach(f => console.log(`   - ${f.file}: ${f.error}`));
        process.exit(1);
    }
}

// Run upload
uploadFolder().catch(error => {
    console.error('❌ Upload failed:', error);
    process.exit(1);
});
EOL

echo "✅ Upload script created: $UPLOAD_SCRIPT"
echo ""

# ============================================
# Install AWS SDK if needed
# ============================================

echo "📦 Checking for AWS SDK dependency..."
if [ ! -f "package.json" ] || ! npm list @aws-sdk/client-s3 2>/dev/null | grep -q "@aws-sdk/client-s3"; then
    echo "Installing @aws-sdk/client-s3..."
    npm install @aws-sdk/client-s3 --no-save
else
    echo "AWS SDK already installed"
fi

# ============================================
# Upload the folder
# ============================================

echo ""
echo "🚀 Starting folder upload..."
echo "================================"

# Set environment variables for the Node script
export DO_ACCESS_KEY="$ACCESS_KEY"
export DO_SECRET_KEY="$SECRET_KEY"
export DO_ENDPOINT="$ENDPOINT"
export DO_REGION="$REGION"
export DO_BUCKET="$BUCKET"
export DO_FOLDER="$FOLDER"
export DO_CDN_ENDPOINT="$CDN_ENDPOINT"
export DO_API_TOKEN="$API_TOKEN"
export DO_CDN_ID="$CDN_ID"

# Run the upload script
node "$UPLOAD_SCRIPT"

# Cleanup
rm -f "$UPLOAD_SCRIPT"

echo ""
echo "🎉 Folder upload completed!"
echo ""

# Show git commands if in a git repo
if [ -d ".git" ]; then
    echo "📝 Git repository detected. You can now:"
    echo "   git add ."
    echo "   git commit -m 'deploy to digital ocean spaces'"
    echo "   git push"
    echo ""
    echo "🌐 For Netlify deployment:"
    echo "   netlify deploy --prod"
fi