default: build

FLAGS += -fobjc-arc
FLAGS += -framework Cocoa
FLAGS += -framework CoreVideo
FLAGS += -framework OpenGL
FLAGS += -I ../skew/src/cpp
FLAGS += -lc++
FLAGS += -o Sky.app/Contents/MacOS/Sky
FLAGS += -std=c++11
FLAGS += -Wno-switch
FLAGS += osx.mm

build:
	mkdir -p Sky.app/Contents/MacOS
	sh -c 'cd .. && make cpp-osx'
	clang $(FLAGS)
