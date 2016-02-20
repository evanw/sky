BUILD = node_modules/.bin/skewc src/*/*.sk --target=js --output-file=www/compiled.js

default: debug

debug: | node_modules
	$(BUILD) --js-source-map

release: | node_modules
	$(BUILD) --release

watch-debug:
	node_modules/.bin/watch src 'clear && make debug && echo done'

watch-release:
	node_modules/.bin/watch src 'clear && make release && echo done'

node_modules:
	npm install
