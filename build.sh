#!/usr/bin/env bash

set -e

echo "Building Shoebill Strike..."
echo ""

echo "Step 1: Building shared package..."
cd shared
gleam build
gleam test
cd ..
echo "✅ Shared package built and tested"
echo ""

echo "Step 2: Building client..."
cd client
gleam build
gleam test
echo "Building client bundle..."
gleam run -m lustre/dev build --minify --no-html --outdir=../server/priv/static
cp index.html ../server/priv/static/index.html
cd ..
echo "Building Tailwind CSS..."
tailwindcss -i client/tailwind.css -o server/priv/static/styles.css --minify
cd client
echo "✅ Client built and bundled"
echo ""

echo "Step 3: Building server..."
cd ../server
gleam build
gleam test
echo "✅ Server built and tested"
echo ""

echo "🎉 Build complete!"
echo ""
echo "To run the server:"
echo "  cd server && gleam run"
