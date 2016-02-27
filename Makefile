SKEW = node skew/skewc.js src/*/*.sk --message-limit=0
GLSLX = node_modules/.bin/glslx glslx/shaders.glslx --format=skew --output=src/graphics/shaders.sk

FLAGS_JS += --output-file=www/compiled.js
FLAGS_JS += --define:BUILD=BROWSER

FLAGS_OSX += --output-file=osx/compiled.cpp
FLAGS_OSX += --define:BUILD=NATIVE

default: debug

shaders:
	$(GLSLX)

debug: | node_modules
	$(SKEW) $(FLAGS_JS)

profile: | node_modules
	$(SKEW) $(FLAGS_JS) --release --js-mangle=false --js-minify=false

release: | node_modules
	$(SKEW) $(FLAGS_JS) --release

cpp-osx-debug: | node_modules
	$(SKEW) $(FLAGS_OSX)

cpp-osx-release: | node_modules
	$(SKEW) $(FLAGS_OSX) --fold-constants --inline-functions

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
