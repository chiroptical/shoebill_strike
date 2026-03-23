build:
	bash build.sh

format:
	pushd server && gleam format && popd
	pushd client && gleam format && popd
	pushd shared && gleam format && popd

css:
	tailwindcss -i client/tailwind.css -o server/priv/static/styles.css

css-watch:
	tailwindcss -i client/tailwind.css -o server/priv/static/styles.css --watch

dev-client: client-build css
	npx serve server/priv/static -s -l 3000

client-build:
	pushd client && cp index.html ../server/priv/static/index.html
	pushd client && gleam run -m lustre/dev build --no-html --outdir=../server/priv/static

.PHONY: build format css css-watch dev-client client-build
