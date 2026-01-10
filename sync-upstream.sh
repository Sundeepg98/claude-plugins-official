#!/bin/bash
# Sync fork with upstream while preserving Windows fixes

set -e

echo "🔄 Fetching upstream..."
git fetch upstream

echo "📋 Upstream changes:"
git log main..upstream/main --oneline

read -p "Merge these changes? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git merge upstream/main
    
    if [ $? -ne 0 ]; then
        echo "⚠️  Conflicts detected! Resolve them, then:"
        echo "   - Keep normalize_path() in stop-hook.sh"
        echo "   - Keep .cmd reference in hooks.json"
        echo "   - Keep promise detection fix in stop-hook.sh"
        exit 1
    fi
    
    echo "✅ Merged successfully!"
    echo "📤 Push with: git push origin main"
fi
