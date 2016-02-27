default: debug

FLAGS += -fobjc-arc
FLAGS += -framework Cocoa
FLAGS += -framework CoreVideo
FLAGS += -framework OpenGL
FLAGS += -I ../skew/src/cpp
FLAGS += -lc++
FLAGS += -o Sky.app/Contents/MacOS/Sky
FLAGS += -std=c++11
FLAGS += -Wall
FLAGS += -Wextra
FLAGS += -Wl,-sectcreate,__TEXT,__info_plist,Sky.app/Contents/Info.plist
FLAGS += -Wno-switch
FLAGS += -Wno-unused-parameter
FLAGS += osx.mm

debug:
	mkdir -p Sky.app/Contents/MacOS
	sh -c 'cd .. && make cpp-osx-debug'
	echo '<plist version="1.0"><dict><key>NSHighResolutionCapable</key><true/></dict></plist>' > Sky.app/Contents/Info.plist
	clang $(FLAGS)
	rm Sky.app/Contents/Info.plist

release:
	mkdir -p Sky.app/Contents/MacOS
	sh -c 'cd .. && make cpp-osx-release'
	echo '<plist version="1.0"><dict><key>NSHighResolutionCapable</key><true/></dict></plist>' > Sky.app/Contents/Info.plist
	clang $(FLAGS) -O3 -DNDEBUG -fomit-frame-pointer
	rm Sky.app/Contents/Info.plist
