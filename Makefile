SKEW = node_modules/.bin/skewc src/*/*.sk --target=js --output-file=www/compiled.js --message-limit=0
GLSLX = node_modules/.bin/glslx glslx/shaders.glslx --format=skew --output=src/graphics/shaders.sk

default: debug

shaders:
	$(GLSLX)

debug: | node_modules
	$(SKEW) --js-source-map

release: | node_modules
	$(SKEW) --release && rm -f www/compiled.js.map

watch-shaders:
	node_modules/.bin/watch glslx 'clear && make shaders && echo done'

watch-debug:
	node_modules/.bin/watch src 'clear && make debug'

watch-release:
	node_modules/.bin/watch src 'clear && make release'

node_modules:
	npm install
