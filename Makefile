SKEW = node_modules/.bin/skewc src/*/*.sk --target=js --output-file=www/compiled.js --message-limit=0
GLSLX = node_modules/.bin/glslx glslx/shaders.glslx --format=skew --output=src/graphics/shaders.sk

default: debug

shaders:
	$(GLSLX)

debug: | node_modules
	$(SKEW)

profile: | node_modules
	$(SKEW) --release --js-mangle=false --js-minify=false

release: | node_modules
	$(SKEW) --release

watch-shaders:
	node_modules/.bin/watch glslx 'clear && make shaders && echo done'

watch-debug:
	node_modules/.bin/watch src 'clear && make debug'

watch-profile:
	node_modules/.bin/watch src 'clear && make profile'

watch-release:
	node_modules/.bin/watch src 'clear && make release'

node_modules:
	npm install
