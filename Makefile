SKEW = node_modules/.bin/skewc src/*/*.sk --message-limit=0
GLSLX = node_modules/.bin/glslx glslx/shaders.glslx --format=skew --output=src/graphics/shaders.sk

SKEW_FLAGS_JS += --output-file=www/compiled.js
SKEW_FLAGS_JS += --define:BUILD=BROWSER

SKEW_FLAGS_OSX += --output-file=osx/compiled.cpp
SKEW_FLAGS_OSX += --define:BUILD=NATIVE

INFO_PLIST_DATA = '<plist version="1.0"><dict><key>NSHighResolutionCapable</key><true/></dict></plist>'
INFO_PLIST_PATH = osx/Sky.app/Contents/Info.plist
OSX_APP_PATH = osx/Sky.app/Contents/MacOS/Sky

CLANG_FLAGS_OSX += -fobjc-arc
CLANG_FLAGS_OSX += -framework Cocoa
CLANG_FLAGS_OSX += -framework CoreVideo
CLANG_FLAGS_OSX += -framework OpenGL
CLANG_FLAGS_OSX += -I skew/src/cpp
CLANG_FLAGS_OSX += -lc++
CLANG_FLAGS_OSX += -o $(OSX_APP_PATH)
CLANG_FLAGS_OSX += -std=c++11
CLANG_FLAGS_OSX += -Wall
CLANG_FLAGS_OSX += -Wextra
CLANG_FLAGS_OSX += -Wl,-sectcreate,__TEXT,__info_plist,$(INFO_PLIST_PATH)
CLANG_FLAGS_OSX += -Wno-switch
CLANG_FLAGS_OSX += -Wno-unused-parameter
CLANG_FLAGS_OSX += osx/osx.mm

default: debug

shaders: | node_modules
	$(GLSLX)

debug: | node_modules
	$(SKEW) $(SKEW_FLAGS_JS)

profile: | node_modules
	$(SKEW) $(SKEW_FLAGS_JS) --release --js-mangle=false --js-minify=false

release: | node_modules
	$(SKEW) $(SKEW_FLAGS_JS) --release

osx-debug: | node_modules
	mkdir -p $(shell dirname $(OSX_APP_PATH))
	$(SKEW) $(SKEW_FLAGS_OSX)
	echo $(INFO_PLIST_DATA) > $(INFO_PLIST_PATH)
	clang $(CLANG_FLAGS_OSX)
	rm $(INFO_PLIST_PATH)

osx-release: | node_modules
	mkdir -p $(shell dirname $(OSX_APP_PATH))
	$(SKEW) $(SKEW_FLAGS_OSX) --release
	echo $(INFO_PLIST_DATA) > $(INFO_PLIST_PATH)
	clang $(CLANG_FLAGS_OSX) -O3 -DNDEBUG -fomit-frame-pointer
	rm $(INFO_PLIST_PATH)

watch-shaders: | node_modules
	node_modules/.bin/watch glslx 'clear && make shaders && echo done'

watch-debug: | node_modules
	node_modules/.bin/watch src 'clear && make debug'

watch-profile: | node_modules
	node_modules/.bin/watch src 'clear && make profile'

watch-release: | node_modules
	node_modules/.bin/watch src 'clear && make release'

node_modules:
	npm install
